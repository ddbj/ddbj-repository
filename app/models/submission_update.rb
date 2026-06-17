class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  enum :source, {
    manual:    0,
    migration: 1,
    batch:     2
  }, validate: true

  belongs_to :submission, inverse_of: :updates

  # No maximum — patch sizes can legitimately reach GB scale (genome
  # assemblies, multi-K-sample BS submissions). The DB-side check is
  # nonempty only (octet_length(patch) > 0), and Postgres bytea's
  # ~1GB practical ceiling is the real upper bound.
  validates :patch, length: {minimum: 1}

  # Single canonical invalidator for the parent Submission's cached
  # materialised_record. Firing on create AND destroy keeps the cache
  # column's invariant simple: `cached_at_update_id` is non-nil iff no
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

  # Memoised parse of the bytea-stored JSON Patch. Returns the RFC 6902
  # operation array.
  def parsed_patch
    @parsed_patch ||= Oj.load(patch, mode: :strict)
  end

  def op_count
    parsed_patch.length
  end

  private

  def invalidate_submission_cache!
    Submission.where(id: submission_id).update_all(
      cached_materialised_record: nil,
      cached_at_update_id:        nil
    )
  end
end
