class SubmissionRequest < ApplicationRecord
  include ValidationSubject

  belongs_to :user
  belongs_to :submission, optional: true, inverse_of: :request

  has_one_attached :ddbj_record
end
