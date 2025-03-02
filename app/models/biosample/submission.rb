class BioSample::Submission < BioSample::Record
  self.table_name = "submission"

  belongs_to :form, class_name: "BioSample::SubmissionForm", foreign_key: "submission_id"

  has_many :samples,  class_name: "BioSample::Sample",  foreign_key: "submission_id"
  has_many :contacts, class_name: "BioSample::Contact", foreign_key: "submission_id"
end
