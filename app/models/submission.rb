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

  # Materialise the current state of the record by replaying every
  # SubmissionUpdate's JSON Patch from the empty document. Returns nil when
  # there are no updates yet (a freshly inserted Submission row pre-baseline).
  # Raises MaterialisationFailed (carrying the offending update_id) when any
  # patch fails to apply, so callers can localise the poisoned row.
  #
  # Phase 3 spike: lazy, no cache. canonical-json.md §1.6 prescribes a
  # write-through cache when 30-patch chains start to bite latency budgets
  # — defer until measured.
  def materialised_record
    materialise_at
  end

  # Replay submission_updates up to and including `update_id` (defaults to
  # the most recent). Used both for the show page's default render and for
  # `?as_of=N` point-in-time snapshots.
  def materialise_at(update_id: nil)
    scope = updates.order(:id)
    # Guard with `&.positive?` so caller bugs that pass 0 / negative ids
    # don't accidentally trigger `id <= 0`, which would silently return an
    # empty replay even when the submission has updates.
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
  # against the same stale base and produce a divergent chain whose later
  # replay raises MaterialisationFailed.
  #
  # NOTE on volatile fields (canonical-json.md §4.2 asymmetry): diff strips
  # `/provenance` / `/**/accession` / etc. on BOTH sides, while apply is
  # pure RFC 6902 and leaves them intact during replay. The combination
  # means volatile keys introduced by a migration-source baseline stick
  # around — there is no append_update! path that can remove them.
  # Migration baselines should avoid writing volatile fields if downstream
  # curator edits need to be able to clear them.
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
    end
  end
end
