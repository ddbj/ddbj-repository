class BioSample::Contact < BioSample::Record
  self.table_name = "contact"

  belongs_to :submission, class_name: "BioSample::Submission", foreign_key: "submission_id"
end
