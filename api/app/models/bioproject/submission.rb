class BioProject::Submission < BioProject::BaseRecord
  self.table_name = "submission"

  has_one  :project,         class_name: "BioProject::Project"
  has_many :xmls,            class_name: "BioProject::XML"
  has_many :submission_data, class_name: "BioProject::SubmissionDatum"

  enum :status_id, {
    data_submitted: 700
  }
end
