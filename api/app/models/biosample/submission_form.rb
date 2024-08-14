class BioSample::SubmissionForm < BioSample::Record
  self.table_name = "submission_form"

  enum :release_type, {
    hold:    1,
    release: 2
  }

  enum :status_id, {
    new: 100
  }, prefix: true
end
