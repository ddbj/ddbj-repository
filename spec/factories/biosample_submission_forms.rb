FactoryBot.define do
  factory :biosample_submission_form, class: "BioSample::SubmissionForm" do
    submitter_id { "alice" }
    status_id    { :data_submitted }
  end
end
