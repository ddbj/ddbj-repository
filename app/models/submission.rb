class Submission < ApplicationRecord
  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :user
  belongs_to :cached_at_update, class_name: 'SubmissionUpdate', optional: true

  has_one :request, dependent: :destroy, class_name: 'SubmissionRequest'

  has_many :updates,    dependent: :destroy, class_name: 'SubmissionUpdate'
  has_many :accessions, dependent: :destroy

  has_one  :project, dependent: :destroy
  has_many :samples, dependent: :destroy

  has_one_attached :ddbj_record
  has_one_attached :current_record
  has_one_attached :flatfile_na
  has_one_attached :flatfile_aa

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
  # Caches the latest-snapshot bytes in the `cached_materialised_record`
  # bytea column and stamps `cached_at_update_id` with the update id
  # the cache reflects. On the next read, if `cached_at_update_id ==
  # updates.max(:id)` the column is parsed directly without replay.
  #
  # bytea (not ActiveStorage) so the cache read is a single column fetch
  # — no SeaweedFS round trip in production. BS records with ~20K
  # samples land around 2-3MB, well within Postgres row toasting.
  #
  # `materialise_at(update_id:)` for historical snapshots does NOT
  # consult the cache — only the latest-state path is cached.
  def materialised_record
    latest_id = updates.maximum(:id)
    return nil unless latest_id

    if cached_at_update_id == latest_id && cached_materialised_record.present?
      return Oj.load(cached_materialised_record, mode: :strict)
    end

    fresh = materialise_at(update_id: latest_id)
    write_through_cache(fresh, latest_id) if fresh

    fresh
  end

  # Replay submission_updates up to and including `update_id` (defaults
  # to the most recent). Used for `?as_of=N` historical snapshots; the
  # cache-aware fast path lives on materialised_record.
  def materialise_at(update_id: nil)
    scope = updates.order(:id)
    scope = scope.where('submission_updates.id <= ?', update_id) if update_id&.positive?
    rows  = scope.pluck(:id, :patch)
    return nil if rows.empty?

    rows.reduce({}) {|state, (id, raw)|
      begin
        DDBJRecord::Canonicalizer.apply(state, Oj.load(raw, mode: :strict))
      rescue StandardError => e
        raise MaterialisationFailed.new(update_id: id, original: e)
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
      patch = DDBJRecord::Canonicalizer.diff(materialised_record || {}, new_record)
      return nil if patch.empty?

      updates.create!(
        db:                       db,
        status:                   :applied,
        actor:                    actor,
        source:                   source,
        patch:                    Oj.dump(patch, mode: :strict),
        patch_canonical_version:  1
      )
      # Cache invalidates passively — the next materialised_record sees
      # cached_at_update_id < latest_id and recomputes + re-caches.
    end
  end

  private

  def write_through_cache(record, update_id)
    update_columns(
      cached_materialised_record: Oj.dump(record, mode: :strict),
      cached_at_update_id:        update_id
    )
  rescue StandardError => e
    # Cache write failure must not break the read path — `fresh` is
    # already in hand. Worth a Sentry breadcrumb so persistent cache
    # write failures (toast row limits, etc.) get noticed.
    Rails.error.report e, context: {submission_id: id, update_id: update_id}
  end
end
