class Submission < ApplicationRecord
  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  has_one :request, dependent: :destroy, class_name: 'SubmissionRequest'

  has_many :updates,    dependent: :destroy, class_name: 'SubmissionUpdate'
  has_many :accessions, dependent: :destroy

  has_one_attached :ddbj_record
  has_one_attached :flatfile_na
  has_one_attached :flatfile_aa

  validates :ddbj_record, attached: true, content_type: 'application/json', on: :update

  after_destroy do |submission|
    submission.dir.rmtree
  end

  def dir
    base = Rails.application.config_for(:app).repository_dir!

    Pathname.new(base).join(request.user.uid, 'submissions', id.to_s)
  end
end
