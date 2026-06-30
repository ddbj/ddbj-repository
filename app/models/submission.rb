class Submission < ApplicationRecord
  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :user

  has_one :request, dependent: :destroy, class_name: 'SubmissionRequest'

  has_many :updates,    dependent: :destroy, class_name: 'SubmissionUpdate'
  has_many :accessions, dependent: :destroy

  has_one  :project, dependent: :destroy
  has_many :samples, dependent: :destroy

  has_many :messages, -> { chronological }, class_name: 'SubmissionMessage', dependent: :destroy

  has_many :sample_tsv_imports, -> { recent }, dependent: :destroy

  has_one_attached :ddbj_record
  has_one_attached :current_record
  has_one_attached :flatfile_na
  has_one_attached :flatfile_aa

  # Latest-materialised snapshot, blob-backed so the cumulative size
  # follows the same ceiling story as SubmissionUpdate#patch (see
  # [[project-submission-update-patch-size-ceiling]]).
  has_one_attached :cached_materialised_record

  validates :ddbj_record, attached: true, content_type: 'application/json', on: :update

  after_destroy do |submission|
    submission.dir.rmtree
  end

  def dir
    base = Rails.application.config_for(:app).repository_dir!

    Pathname.new(base).join(user.uid, 'submissions', id.to_s)
  end

  class MaterialisationFailed < StandardError
    attr_reader :update_id, :original

    def initialize(update_id:, original:)
      @update_id = update_id
      @original  = original
      super("SubmissionUpdate ##{update_id} replay failed: #{original.class}: #{original.message}")
    end
  end

  # Materialise the current state by replaying every SubmissionUpdate's
  # JSON Patch from {}. Returns nil if there are no updates yet.
  #
  # Caches the latest-snapshot bytes in `cached_materialised_record`
  # (ActiveStorage). Invariant: `cached_at_update_id` is non-nil iff the
  # cache is fresh — SubmissionUpdate#after_create and #after_destroy
  # (in-transaction hooks, not _commit; see submission_update.rb)
  # unconditionally nil-clear the stamp, so any chain edit (append,
  # undo, intermediate delete) invalidates. That lets the read path
  # short-circuit on column presence alone without a round trip to
  # submission_updates.
  #
  # `materialise_at(update_id:)` for historical snapshots does NOT
  # consult the cache — only the latest-state path is cached.
  def materialised_record
    if cached_at_update_id.present? && cached_materialised_record.attached?
      return Oj.load(cached_materialised_record.download, mode: :strict)
    end

    latest_id = updates.maximum(:id)
    return nil unless latest_id

    fresh = materialise_at(update_id: latest_id)
    write_through_cache(fresh, latest_id) if fresh

    fresh
  end

  # Raw cached bytes for the latest snapshot, or nil when the cache is
  # cold. Lets callers (e.g. the admin `materialised` controller) ship
  # the bytes verbatim without paying for Oj.load + re-encode.
  def cached_materialised_bytes
    return nil unless cached_at_update_id.present? && cached_materialised_record.attached?

    cached_materialised_record.download
  end

  # True iff the cached snapshot's bytes are identical to `dump`.
  # Compares ActiveStorage's pre-computed checksum (base64 MD5) instead
  # of downloading the full blob — used by the importer fast-skip path
  # so a 7MB BS record doesn't round-trip from SeaweedFS just to test
  # for "no semantic change since last import".
  def cached_record_matches_dump?(dump)
    blob = cached_materialised_record.blob
    return false unless blob

    blob.checksum == Digest::MD5.base64digest(dump)
  end

  # Replay submission_updates up to and including `update_id` (defaults
  # to the most recent). Used for `?as_of=N` historical snapshots; the
  # cache-aware fast path lives on materialised_record.
  def materialise_at(update_id: nil)
    scope = updates.order(:id).with_attached_patch
    scope = scope.where('submission_updates.id <= ?', update_id) if update_id&.positive?
    rows  = scope.to_a
    return nil if rows.empty?

    rows.reduce({}) {|state, update|
      begin
        DDBJRecord::Canonicalizer.apply(state, update.parsed_patch)
      rescue StandardError => e
        raise MaterialisationFailed.new(update_id: update.id, original: e)
      end
    }
  end

  # Compute a JSON Patch from the current materialised state to
  # `new_record`, append it as a new SubmissionUpdate, and return that
  # update. Returns nil (no-op) when the canonical diff is empty.
  #
  # Wrapped in `with_lock` so a row-level lock on the parent Submission
  # serialises concurrent appenders — without it two callers would diff
  # against the same stale base and produce a divergent chain.
  #
  # NOTE on volatile fields (canonical-json.md §4.2 asymmetry): diff
  # strips `/provenance` / `/**/accession` / etc. on BOTH sides, while
  # apply is pure RFC 6902 and leaves them intact during replay. The
  # combination means volatile keys introduced by a migration-source
  # baseline stick around — there is no append_update! path that can
  # remove them.
  def append_update!(new_record, actor:, source: :manual)
    with_lock do
      latest_id = updates.maximum(:id)
      base      = latest_id ? materialise_at(update_id: latest_id) : {}

      # Try a minimal semantic diff. If it lands inside a bag-mode array
      # (or any other Canonicalizer::Error — NumberGuard, ControlChar,
      # OrderedEmptyElement, etc.) fall back to a root-level snapshot.
      # That loses per-field chain granularity for THIS op but keeps
      # curator edits on bag-internal fields (e.g. submitter
      # organizations) replayable. Mirrors the same fallback used by
      # BP/BS Importer's `compute_patch_ops`.
      patch = begin
        DDBJRecord::Canonicalizer.diff(base, new_record)
      rescue DDBJRecord::Canonicalizer::Error
        op = base.empty? ? 'add' : 'replace'
        [{'op' => op, 'path' => '', 'value' => new_record}]
      end
      return nil if patch.empty?

      SubmissionUpdate.create_with_patch!(
        submission:              self,
        patch_json:              Oj.dump(patch, mode: :strict),
        db:                      db,
        status:                  :applied,
        actor:                   actor,
        source:                  source,
        patch_canonical_version: 1
      )
      # Cache invalidates via SubmissionUpdate#after_create (inside this
      # transaction) — no explicit clear here. Deliberately bypassing the
      # cached read (using materialise_at directly) because we are about
      # to invalidate the cache anyway, so consuming it would be wasted IO.
    end
  end

  # Upload the freshly-computed snapshot bytes and stamp the cache
  # marker. The blob is uploaded synchronously OUTSIDE the row lock —
  # `attach(blob)` for a pre-uploaded Blob skips ActiveStorage's
  # after_commit upload deferral (CreateOne#upload has an empty
  # `when Blob` branch), so a subsequent `download` in the SAME
  # transaction sees the file. The row lock then covers only the
  # stamp/attachment swap so a slower concurrent writer cannot tear
  # the (blob, stamp) pair; if a fresher cache already won, the
  # already-uploaded blob is purged.
  #
  # `save!(validate: false)` skips the `validates :ddbj_record, ...,
  # on: :update` rule — migration-sourced submissions don't carry a
  # ddbj_record blob, and the cache write shouldn't be gated on the
  # API ingest contract.
  #
  # ORPHAN CAVEAT: same as SubmissionUpdate.create_with_patch! — an
  # outer-transaction rollback after the synchronous SeaweedFS PUT
  # leaves the file on storage with no DB row. Periodic unattached-blob
  # sweep is the right long-term cleanup; not yet wired up.
  def prime_cache!(bytes:, update_id:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           StringIO.new(bytes),
      filename:     "materialised-#{update_id}.json",
      content_type: 'application/json'
    )

    with_lock do
      if cached_at_update_id && cached_at_update_id > update_id
        blob.purge_later
        next
      end

      self.cached_materialised_record = blob
      self.cached_at_update_id        = update_id
      save!(validate: false)
    end
  rescue StandardError
    blob&.purge_later
    raise
  end

  private

  def write_through_cache(record, update_id)
    prime_cache!(bytes: Oj.dump(record, mode: :strict), update_id: update_id)
  rescue StandardError => e
    # Cache write failure must not break the read path — `record` is
    # already in hand. Sentry breadcrumb so persistent failures
    # (SeaweedFS down, FK violations, etc.) get noticed.
    Rails.error.report e, context: {submission_id: id, update_id: update_id}
  end
end
