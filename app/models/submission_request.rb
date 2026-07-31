class SubmissionRequest < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :user
  belongs_to :submission, optional: true, inverse_of: :request

  has_many :messages, -> { chronological }, class_name: 'SubmissionMessage', dependent: :destroy

  has_one :reviewer_access, dependent: :destroy

  has_one_attached :ddbj_record

  # A request is "assigned to" a curator when the curation rows behind it
  # — the BP Project, or any of the BS Samples — carry that assignee. A
  # request with no submission yet has no curation rows and is therefore
  # never in anybody's queue, which is exactly right: it belongs to the
  # "Not applied yet" bucket instead.
  scope :curated_by, ->(user) {
    where(<<~SQL.squish, assignee_id: user.id)
      EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.assignee_id = :assignee_id) OR
      EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.assignee_id  = :assignee_id)
    SQL
  }

  # Interactive requests always carry the uploaded JSON. Synthetic
  # requests minted by the BP/BS importer (marked by migration_run_id)
  # wrap an already-materialised submission and have no upload, so the
  # attachment rule is waived for them.
  validates :ddbj_record, attached: true, content_type: 'application/json', unless: :migration_origin?

  def migration_origin?
    migration_run_id.present?
  end
end
