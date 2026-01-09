class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  belongs_to :submission, inverse_of: :updates

  has_one_attached :ddbj_record

  validates :ddbj_record, attached: true, content_type: 'application/json'
end
