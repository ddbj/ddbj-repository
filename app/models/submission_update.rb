class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  enum :source, {
    manual:     0,
    migration:  1,
    batch:      2,
    tsv_import: 3
  }, validate: true

  belongs_to :submission, inverse_of: :updates

  # Patch JSON lives in object storage (SeaweedFS in production, Disk in
  # test) so it can exceed Postgres bytea's ~1GB practical ceiling — see
  # [[project-submission-update-patch-size-ceiling]]. `dependent:
  # :purge_later` (the default) cleans up the blob when the row is
  # destroyed.
  has_one_attached :patch

  validates :patch, attached: true
  validate  :patch_blob_nonempty

  # Single canonical invalidator for the parent Submission's cached
  # materialised_record. Firing on create AND destroy keeps the cache
  # invariant simple: `cached_at_update_id` is non-nil iff no
  # SubmissionUpdate has been created or destroyed since the cache was
  # written. With this guarantee the read path can short-circuit on
  # `cached_at_update_id.present?` without re-querying the updates table.
  #
  # In-transaction (after_create / after_destroy, not _commit) so a
  # rolled-back SubmissionUpdate write also rolls back the cache
  # invalidation — the chain composition only "changed" if the write
  # actually lands.
  after_create  :invalidate_submission_cache!
  after_destroy :invalidate_submission_cache!

  # Insert a SubmissionUpdate and attach its JSON-Patch body atomically.
  # Uploads the blob synchronously (via `Blob.create_and_upload!`) and
  # then assigns it through the standard setter: a caller that creates
  # an update and immediately replays the chain inside the same
  # transaction (importer, append_update! during diff-base
  # materialisation) needs the bytes downloadable RIGHT NOW. The
  # ordinary `attach(io:, filename:)` API would defer the upload to
  # after_commit and surface a FileNotFoundError on the in-transaction
  # download. Passing an already-uploaded Blob to the setter skips the
  # deferred-upload branch (CreateOne#upload is a no-op for Blob input).
  # The setter-queued change makes `validates :patch, attached: true`
  # pass at save time, and the attachment row is autosaved with the
  # parent. If the parent save raises, the orphan blob is purged.
  #
  # ORPHAN CAVEAT: if the SURROUNDING transaction (e.g. the importer's
  # `Submission.transaction`) rolls back AFTER save! returned, the blob
  # row is rolled back with it but the SeaweedFS file PUT already
  # happened — no DB pointer remains to schedule purge. A periodic
  # unattached-blob sweep (or `ActiveStorage::PurgeJob.set(wait:) on a
  # post-commit hook) is the right long-term cleanup; not yet wired up.
  def self.create_with_patch!(submission:, patch_json:, **attrs)
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           StringIO.new(patch_json),
      filename:     'patch.json',
      content_type: 'application/json'
    )

    submission.updates.build(**attrs).tap {
      it.patch = blob
      it.save!
    }
  rescue StandardError
    blob&.purge_later
    raise
  end

  # Memoised parse of the attached JSON Patch body. Returns the RFC 6902
  # operation array. For BP/BS scale (≤ 100 MB) downloading + Oj.load
  # remains in-memory; Trad-scale streaming is documented as a follow-up
  # on [[project-submission-update-patch-size-ceiling]].
  def parsed_patch
    @parsed_patch ||= Oj.load(patch.download, mode: :strict)
  end

  def op_count
    parsed_patch.length
  end

  private

  # Defence in depth for the dropped bytea `length: { minimum: 1 }` +
  # CHECK constraint. `attached: true` only asserts the association is
  # set, so a zero-byte StringIO would otherwise sail through and only
  # surface later as a cryptic `Oj::ParseError` during chain replay.
  def patch_blob_nonempty
    return unless patch.attached?
    return if patch.blob.byte_size.positive?

    errors.add(:patch, 'must not be empty')
  end

  def invalidate_submission_cache!
    # Only the stamp is cleared — the attached blob is left in place. On
    # the next cache warm-up `cached_materialised_record.attach(...)`
    # replaces it and schedules purge_later on the previous blob, so
    # orphan growth is bounded in steady state. If no read ever re-warms
    # (rare edge case), the orphan blob sits until the parent Submission
    # is destroyed, at which point has_one_attached's default
    # dependent: :purge_later cleans it up.
    Submission.where(id: submission_id).update_all(cached_at_update_id: nil)
  end
end
