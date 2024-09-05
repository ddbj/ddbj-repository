class BioProject::ActionHistory < BioProject::Record
  self.table_name = "action_histroy"

  belongs_to :submission, class_name: "BioProject::Submission"
end
