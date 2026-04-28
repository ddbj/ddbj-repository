class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :submission, inverse_of: :updates

  has_one_attached :ddbj_record

  validates :ddbj_record, attached: true, content_type: 'application/json'
end
