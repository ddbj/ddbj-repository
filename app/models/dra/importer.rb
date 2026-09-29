# frozen_string_literal: true

# One DRA submission from D-way (DRA::StagingClient::Submission) into the
# repository: a Submission of db `dra` owned by its submitter, its
# DRASubmission row, and a patch chain that replays D-way's history — one
# patch for each version the submission was saved in, dated when it was
# saved.
#
# Re-running brings the chain up to D-way: the versions saved after the
# last one read (DRASubmission#version_saved_at) are appended — and the
# latest state again, if its documents are no longer the ones last read
# (#version_digest): an object deleted after the last send, or a version
# dated before the one it follows, changes it without a later save.
# Nothing else is written to the chain. D-way is where DRA is edited until the repository
# takes submissions itself, so a version saved there after a curator's edit
# here is written over that edit, as the BioProject and BioSample imports
# do.
#
# The DRASubmission row is D-way's account of where the submission stands
# (status and dates), and is refreshed on every run: those move in D-way
# without a new version — a submission goes public by its status changing,
# not its XML.
class DRA::Importer
  include DataMigration::ChainImport

  class CrossUserError < StandardError; end

  Result = Data.define(:submission, :outcome) # :created | :updated | :skipped | :no_versions | :no_accession

  # dracommon's SubmissionStatus, from ACC_ISSUED on (what is imported).
  STATUSES = {
    500  => :accession_issued,
    700  => :private,
    770  => :temporarily_suppressed,
    800  => :public,
    1000 => :canceled,
    1100 => :permanently_suppressed,
    1200 => :withdrawn
  }.freeze

  def initialize(row, migration_run_id:)
    @row              = row
    @migration_run_id = migration_run_id
  end

  def call
    return Result.new(submission: nil, outcome: :no_versions)  if @row.versions.empty?
    return Result.new(submission: nil, outcome: :no_accession) unless @row.accession

    Submission.transaction do
      user       = User.find_or_create_by!(uid: @row.submitter_id)
      submission = Submission.find_or_create_by!(db: :dra, source_id: @row.accession) {|s|
        s.user              = user
        s.migration_run_id  = @migration_run_id
        s.canonical_version = DDBJRecord::Canonicalizer::NUMBER
        s.created_at        = @row.versions.first.saved_at
      }

      if submission.user_id != user.id
        raise CrossUserError,
              "Submission #{@row.accession} already exists under user '#{submission.user.uid}'; " \
              "refusing to silently re-attribute to '#{@row.submitter_id}'."
      end

      submission.ensure_migration_request!(migration_run_id: @migration_run_id, submitted_at: @row.versions.first.saved_at)

      row = submission.dra_submission || submission.build_dra_submission

      row.assign_attributes(
        accession:          @row.accession,
        status:             STATUSES.fetch(@row.status) { raise ArgumentError, "unknown DRA status #{@row.status.inspect}" },
        hold_date:          @row.hold_date,
        first_published_at: @row.release_date,

        # drmdb dates the change of status, so the moment a submission left
        # public is known here, where BioProject and BioSample have only the
        # row's last change.
        last_published_at: DataMigration::DwayDefaults.last_published_at(
          public:   STATUSES[@row.status] == :public,
          release:  @row.release_date,
          dist:     @row.dist_date&.in_time_zone,
          modified: @row.status_changed_at
        )
      )

      # Checked before the patches are stored: a row refused after them
      # would roll back and leave their objects in the store.
      row.validate!

      outcome = append_versions(submission, row)

      row.save!

      Result.new(submission:, outcome:)
    end
  end

  private

  # The versions saved after the last one read, each as a patch. A version
  # that changes nothing the record says adds none, but is read all the
  # same.
  #
  # Every version is converted and diffed before anything is stored: one
  # that does not convert then leaves no patch objects behind in the store
  # for a transaction that rolled back.
  #
  # A patch is dated when its version was saved, unless the chain already
  # holds something later — a curator's edit here — which it is written
  # over now rather than then.
  #
  # A chain written under an older ddbj-canon is healed by the next patch
  # (a root replace, see ChainImport#compute_patch_ops) or by
  # `rake ddbj_record:reshape_v3`, not by re-reading an old version.
  def append_versions(submission, row)
    pending = pending_versions(row)

    return :skipped if pending.empty?

    first   = submission.updates.none?
    prior   = first ? {} : safe_prior_materialised(submission)
    legacy  = submission.legacy_chain?
    record  = nil
    patches = pending.filter_map {|version|
      record = convert(version, latest: version.equal?(pending.last)) or next
      ops    = compute_patch_ops(prior, record, legacy:)

      next if ops.empty?

      prior  = DDBJRecord::Canonicalizer.apply(prior, ops)
      legacy = false

      [version.saved_at, ops]
    }

    row.version_saved_at = pending.last.saved_at
    row.version_digest   = pending.last.digest

    return :skipped if patches.empty?

    since  = submission.updates.maximum(:created_at)
    update = patches.map {|saved_at, ops|
      SubmissionUpdate.create_with_patch!(
        submission:,
        patch_json:              Oj.dump(ops, mode: :strict),
        db:                      'dra',
        status:                  :applied,
        actor:                   "migration:#{@row.submitter_id}",
        source:                  :migration,
        patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER,
        created_at:              [saved_at, since].compact.max
      )
    }.last

    submission.update_columns(
      canonical_version: DDBJRecord::Canonicalizer::NUMBER,
      converter_version: "dra_v3/#{DRA::Converter::SOURCE_FORMAT}",
      migration_run_id:  @migration_run_id,
      source_checksum:   Submission.source_checksum_of(record),
      updated_at:        Time.current
    )

    submission.prime_cache!(bytes: Oj.dump(prior, mode: :strict), update_id: update.id)

    first ? :created : :updated
  end

  # A version whose XML does not parse is no state SRA XML can describe,
  # and so none the record can: it is left out of the chain, and the next
  # version that parses is taken as following the one before. Reported,
  # since the chain is then shorter than D-way's history. Seen once in the
  # archive (DRA015605, a sample saved twice with a tag missing and put
  # right before it was sent on).
  #
  # Not the latest: that is what the record is, and a record that cannot be
  # read is a failure of the import rather than a gap in the history.
  def convert(version, latest:)
    DRA::Converter.new(documents: version.documents).call
  rescue Nokogiri::XML::SyntaxError => e
    raise if latest

    Rails.error.report e, handled: true, severity: :warning, context: {accession: @row.accession, saved_at: version.saved_at}

    nil
  end

  # What D-way has saved since the last run: the versions saved after the
  # last one read, or else — where the latest state is not the one read —
  # that state, taken as saved now.
  def pending_versions(row)
    latest = @row.versions.last
    after  = @row.versions.select { row.version_saved_at.nil? || it.saved_at > row.version_saved_at }

    return after if after.any? || row.version_digest.nil? || latest.digest == row.version_digest

    [latest.with(saved_at: Time.current)]
  end
end
