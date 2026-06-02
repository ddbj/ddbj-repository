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

  # Materialise the current state of the record by replaying every
  # SubmissionUpdate's JSON Patch from the empty document. Returns nil when
  # there are no updates yet (a freshly inserted Submission row pre-baseline).
  #
  # Phase 3 spike: lazy, no cache. canonical-json.md §1.6 prescribes a
  # write-through cache (`has_one_attached :current_record` blob) when
  # 30-patch chains start to bite latency budgets — defer until measured.
  def materialised_record
    raw_patches = updates.order(:id).pluck(:patch)
    return nil if raw_patches.empty?

    raw_patches.reduce({}) {|state, raw|
      DDBJRecord::Canonicalizer.apply(state, Oj.load(raw, mode: :strict))
    }
  end
end
