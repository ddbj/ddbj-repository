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
  # write-through cache (`has_one_attached :current_record` blob) when
  # 30-patch chains start to bite latency budgets — defer until measured.
  def materialised_record
    rows = updates.order(:id).pluck(:id, :patch)
    return nil if rows.empty?

    rows.reduce({}) {|state, (id, raw)|
      begin
        DDBJRecord::Canonicalizer.apply(state, Oj.load(raw, mode: :strict))
      rescue StandardError => e
        raise MaterialisationFailed.new(update_id: id, original: e)
      end
    }
  end
end
