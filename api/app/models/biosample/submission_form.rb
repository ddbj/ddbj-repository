class BioSample::SubmissionForm < BioSample::Record
  self.table_name = "submission_form"

  enum :release_type, {
    hold:    1,
    release: 2
  }

  enum :status_id, {
    new:             100,
    submitter_ok:    200,
    general_info_ok: 300,
    sample_type_ok:  400,
    attribute_ok:    500,
    publication_ok:  600,
    comment_ok:      650,
    data_submitted:  700,
    data_error:      750
  }, prefix: true
end
