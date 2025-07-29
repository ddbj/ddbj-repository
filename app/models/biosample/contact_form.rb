class BioSample::ContactForm < BioSample::Record
  self.table_name = 'contact_form'

  belongs_to :submission_form, class_name: 'BioSample::SubmissionForm', foreign_key: 'submission_id'
end
