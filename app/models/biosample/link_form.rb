class BioSample::LinkForm < BioSample::Record
  self.table_name = 'link_form'

  belongs_to :submission_form, class_name: 'BioSample::SubmissionForm', foreign_key: 'submission_id'
end
