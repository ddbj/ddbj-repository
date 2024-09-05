class BioProject::ActionHistory < BioProject::Record
  self.table_name = "action_history"

  belongs_to :submission, class_name: "BioProject::Submission", optional: true
end
