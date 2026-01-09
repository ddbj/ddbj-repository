class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  belongs_to :submission, inverse_of: :updates

  has_one_attached :ddbj_record
end
