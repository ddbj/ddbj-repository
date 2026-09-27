# frozen_string_literal: true

# One DRA submission from D-way (DRA::StagingClient::Submission) into the
# repository: a Submission of db `dra` owned by its submitter, its
# DRASubmission row, and a patch chain that replays D-way's history — one
# patch for each version the submission was saved in, dated when it was
# saved.
#
# Re-running brings the chain up to D-way: the versions saved after the
# last one imported are appended, and nothing else is written to it. The
# DRASubmission row is D-way's account of where the submission stands
# (status and dates), and is refreshed on every run, since those move in
# D-way without a new version — a submission goes public by its status
# changing, not its XML.
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

    user = User.find_or_create_by!(uid: @row.submitter_id)

    Submission.transaction do
      submission = Submission.find_or_create_by!(db: :dra, source_id: @row.accession) {|s|
        s.user              = user
        s.migration_run_id  = @migration_run_id
        s.canonical_version = DDBJRecord::Canonicalizer::NUMBER
      }

      if submission.user_id != user.id
        raise CrossUserError,
              "Submission #{@row.accession} already exists under user '#{submission.user.uid}'; " \
              "refusing to silently re-attribute to '#{@row.submitter_id}'."
      end

      submission.ensure_migration_request!(migration_run_id: @migration_run_id)

      (submission.dra_submission || submission.build_dra_submission).update!(
        accession:    @row.accession,
        status:       STATUSES.fetch(@row.status),
        hold_date:    @row.hold_date,
        dist_date:    @row.dist_date,
        release_date: @row.release_date
      )

      Result.new(submission:, outcome: append_versions(submission))
    end
  end

  private

  # The versions saved after the last one this chain holds, each as a patch
  # dated when it was saved. A version that changes nothing the record says
  # adds nothing.
  #
  # A chain written under an older ddbj-canon is healed by the next patch
  # (a root replace, see ChainImport#compute_patch_ops) or by
  # `rake ddbj_record:reshape_v3`, not by re-importing an old version.
  def append_versions(submission)
    imported = submission.updates.where(source: :migration).maximum(:created_at)
    pending  = @row.versions.select { imported.nil? || it.saved_at > imported }
    prior    = pending.any? ? safe_prior_materialised(submission) : {}
    legacy   = submission.legacy_chain?
    record   = nil
    update   = nil

    pending.each do |version|
      record = DRA::Converter.new(documents: version.documents).call
      ops    = compute_patch_ops(prior, record, legacy:)

      next if ops.empty?

      prior  = DDBJRecord::Canonicalizer.apply(prior, ops)
      update = SubmissionUpdate.create_with_patch!(
        submission:,
        patch_json:              Oj.dump(ops, mode: :strict),
        db:                      'dra',
        status:                  :applied,
        actor:                   "migration:#{@row.submitter_id}",
        source:                  :migration,
        patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER,
        created_at:              version.saved_at
      )
      legacy = false
    end

    return :skipped unless update

    submission.update_columns(
      canonical_version: DDBJRecord::Canonicalizer::NUMBER,
      converter_version: "dra_v3/#{DRA::Converter::SOURCE_FORMAT}",
      migration_run_id:  @migration_run_id,
      source_checksum:   Submission.source_checksum_of(record),
      updated_at:        Time.current
    )

    submission.prime_cache!(bytes: Oj.dump(prior, mode: :strict), update_id: update.id)

    imported ? :updated : :created
  end
end
