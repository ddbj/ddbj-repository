# frozen_string_literal: true

module BioSample
  # Wraps one BS submission's worth of writes (Submission + N Sample rows
  # + baseline SubmissionUpdate) in a single transaction.
  #
  # Idempotency model (two levels):
  #   - SubmissionUpdate insert + Submission canonical_version / converter_
  #     version / migration_run_id refresh: gated on a real patch byte
  #     difference. Re-running with identical EAV state returns :skipped
  #     and does not append a duplicate baseline patch nor bump
  #     migration_run_id.
  #   - Sample typed-column sync (accession / sample_name / package /
  #     package_group / env_package / taxonomy_id / organism / status /
  #     title): ALWAYS runs. Some of those columns (package_group,
  #     env_package) live only on the staging row and never reach the
  #     canonical patch, so gating sync on patch-difference would
  #     permanently strand any staging-side updates to them. The trade-
  #     off is that curator edits to typed columns survive only until
  #     the next re-import — Phase 6 needs explicit curator-edit-vs-
  #     staging diff handling.
  #
  # Sample identity (sync_samples!) is position-based against the staging
  # ORDER BY smp_id, NOT accession. That handles the 14% of staging
  # samples that have NULL accession (pre-accession drafts). Phase 6
  # should add a `staging_smp_id` column to the samples table for a
  # stable persistent identity that survives re-ordering / staging
  # smp_id renumbering; the spike's position-based sync is correct only
  # while the staging query remains `ORDER BY smp_id` and no inserts
  # land mid-prefix.
  class Importer
    class CrossUserError < StandardError; end

    Result = Data.define(:submission, :outcome) # :created | :updated | :skipped | :no_samples

    def initialize(staging_submission:, user_uid:, migration_run_id:)
      @row              = staging_submission
      @user_uid         = user_uid
      @migration_run_id = migration_run_id
    end

    def call
      return Result.new(submission: nil, outcome: :no_samples) if @row.samples.empty?

      record = Converter.new(submission: @row).call
      user   = User.find_or_create_by!(uid: @user_uid)

      Submission.transaction do
        submission = Submission.find_or_create_by!(db: :biosample, source_id: @row.ssub_id) {|s|
          s.user             = user
          s.migration_run_id = @migration_run_id
        }

        if submission.user_id != user.id
          raise CrossUserError,
                "Submission #{@row.ssub_id} already exists under user '#{submission.user.uid}'; " \
                "refusing to silently re-attribute to '#{@user_uid}'."
        end

        # Sample typed columns ALWAYS sync — they include staging-only
        # fields (package_group, env_package) that never reach the
        # canonical patch, so the patch-difference skip below cannot
        # protect them without permanently stranding staging updates.
        sync_samples!(submission, record)

        # Semantic diff against the prior materialised state when
        # possible. First-import path: materialised_record is nil →
        # diff({}, record) returns one `add /<top_level_key>` op per
        # top-level key (NOT a single root op — JsonDiff decomposes
        # the missing-everything baseline). Re-import of an unchanged
        # record: diff is empty → :skipped. Real shape delta: minimal
        # RFC 6902 ops.
        #
        # compute_patch_ops falls back to a root-level snapshot when
        # the structural diff (a) would descend into a bag-array
        # element (any inner `/samples/N/...` change trips
        # reject_bag_descent! because intermediate prefixes default to
        # bag mode) or (b) hits any other Canonicalizer::Error
        # (control chars, number guard, sequence alphabet, etc.).
        # safe_prior_materialised swallows MaterialisationFailed so a
        # poisoned historical patch lets the importer self-heal by
        # overwriting forward instead of permanently failing every
        # re-import for that submission.
        prior_record = safe_prior_materialised(submission)
        patch_ops    = compute_patch_ops(prior_record, record)

        if patch_ops.empty?
          # sync_samples! ran above (typed columns ALWAYS sync), so the
          # bad-batch rollback selector
          #   Submission.where(migration_run_id: 'R-bad').destroy_all
          # would miss this row unless we stamp it here too. Bump
          # migration_run_id + updated_at; leave canonical_version /
          # converter_version untouched because the chain itself is
          # unchanged.
          submission.update_columns(
            migration_run_id: @migration_run_id,
            updated_at:       Time.current
          )
          return Result.new(submission:, outcome: :skipped)
        end

        submission.update_columns(
          canonical_version: 1,
          converter_version: "bs_v3/#{Converter::SOURCE_FORMAT}",
          migration_run_id:  @migration_run_id,
          updated_at:        Time.current
        )

        submission.updates.create!(
          db:                      'biosample',
          status:                  :applied,
          actor:                   "migration:#{@user_uid}",
          source:                  :migration,
          patch:                   Oj.dump(patch_ops, mode: :strict),
          patch_canonical_version: 1
        )

        Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
      end
    end

    private

    def safe_prior_materialised(submission)
      submission.materialised_record || {}
    rescue Submission::MaterialisationFailed => e
      Rails.error.report e, context: {submission_id: submission.id, source_id: @row.ssub_id}
      {}
    end

    # Catches the full Canonicalizer::Error hierarchy, not just
    # BagPatchPathError. The other reachable subclasses
    # (ControlCharacterError, IntegerOutOfRangeError, FloatNotAllowedError,
    # UnsupportedValueError, OrderedEmptyElementError, SequenceAlphabetError)
    # come from Normalizer / NumberGuard / SequenceCodec / ArraySorter
    # during the canonicalize pass diff() runs on BOTH sides. Apply, by
    # contrast, is pure RFC 6902 with no validation — so a baseline
    # patch from the pre-this-commit code path can carry bytes that
    # diff() rejects on the very next re-import. Without this widened
    # rescue any such mismatch rolls the whole importer transaction
    # back (including sync_samples!), turning a one-off staging bug
    # into a permanent :failed row.
    def compute_patch_ops(prior, current)
      DDBJRecord::Canonicalizer.diff(prior, current)
    rescue DDBJRecord::Canonicalizer::Error
      op = prior.empty? ? 'add' : 'replace'
      [{'op' => op, 'path' => '', 'value' => current}]
    end

    def sync_samples!(submission, record)
      v3_samples       = record.fetch('samples')
      staging_samples  = @row.samples
      existing_samples = submission.samples.order(:id).to_a

      if v3_samples.length != staging_samples.length
        raise "PSUB #{@row.ssub_id}: v3 sample count (#{v3_samples.length}) " \
              "diverges from staging sample count (#{staging_samples.length})"
      end

      v3_samples.zip(staging_samples).each_with_index do |(v3, staging), idx|
        attrs = {
          accession:     v3['accession'],
          sample_name:   v3['alias'],
          status:        map_status(staging.status_id),
          title:         v3['title'],
          package:       v3['package'],
          package_group: staging.package_group,
          env_package:   staging.env_package,
          taxonomy_id:   v3.dig('organism', 'taxonomy_id'),
          organism:      v3.dig('organism', 'name')
        }

        if (existing = existing_samples[idx])
          existing.update!(attrs)
        else
          submission.samples.create!(attrs)
        end
      end

      # Drop trailing Sample rows whose position is no longer in the
      # staging snapshot (curator removed a sample in D-way). Without
      # this the typed-column view drifts away from the materialised v3
      # record forever.
      existing_samples[v3_samples.length..].to_a.each(&:destroy)
    end

    # BS staging is entirely on the new 5xxx Lifecycleable codes (verified
    # against staging: 0 rows have legacy status_id=700, unlike BP). So
    # the BP `when 700` arm is intentionally absent here.
    def map_status(legacy_status_id)
      case legacy_status_id
      when 5500 then :public
      when 5400 then :private
      when 5600 then :withdrawn
      when 5700 then :canceled
      when 5800 then :permanently_suppressed
      when 5900 then :temporarily_suppressed
      else           :curating
      end
    end
  end
end
