class BioProject::Submission < BioProject::Record
  self.table_name = 'submission'

  has_one :project, class_name: 'BioProject::Project'

  has_many :action_histories, class_name: 'BioProject::ActionHistory'
  has_many :submission_data,  class_name: 'BioProject::SubmissionDatum'
  has_many :xmls,             class_name: 'BioProject::XML'

  enum :status_id, {
    data_submitted: 700
  }
end
