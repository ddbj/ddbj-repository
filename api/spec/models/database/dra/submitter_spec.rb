require "rails_helper"

RSpec.describe Database::DRA::Submitter, type: :model do
  example do
    submission = create(:submission, {
      validation: build(:validation, :valid, {
        user: build(:user, uid: "alice")
      })
    })

    create :obj, validation: submission.validation, _id: "Submission", validity: "valid"
    create :obj, validation: submission.validation, _id: "Experiment", validity: "valid"
    create :obj, validation: submission.validation, _id: "Run",        validity: "valid"
    create :obj, validation: submission.validation, _id: "Analysis",   validity: "valid"

    user_id = create(:submitterdb_login, **{
      submitter_id: "alice"
    }).usr_id

    expect(Net::SSH).to receive(:start)

    Database::DRA::Submitter.new.submit submission

    submission = DRMDB::Submission.sole

    expect(submission).to have_attributes(
      usr_id:       user_id,
      submitter_id: "alice",
      serial:       1
    )

    expect(submission.status_histories.sole).to have_attributes(
      status: "data_validated"
    )

    submission_group = DRMDB::SubmissionGroup.sole

    expect(submission_group).to have_attributes(
      submit_version: 1,
      valid:          true,
      serial_version: 1
    )

    expect(submission_group.accession_entities).to contain_exactly(
      have_attributes(
        alias:       "alice-0001_Submission_0001",
        center_name: "National Institute of Genetics",
        acc_type:    "DRA"
      ),
      have_attributes(
        alias:       "alice-0001_Experiment_0001",
        center_name: "National Institute of Genetics",
        acc_type:    "DRX"
      ),
      have_attributes(
        alias:       "alice-0001_Run_0001",
        center_name: "National Institute of Genetics",
        acc_type:    "DRR"
      ),
      have_attributes(
        alias:       "alice-0001_Analysis_0001",
        center_name: "National Institute of Genetics",
        acc_type:    "DRZ"
      )
    )

    expect(submission_group.meta_entities).to contain_exactly(
      have_attributes(
        meta_version: 1,
        type:         "submission"
      ),
      have_attributes(
        meta_version: 1,
        type:         "experiment"
      ),
      have_attributes(
        meta_version: 1,
        type:         "run"
      ),
      have_attributes(
        meta_version: 1,
        type:         "analysis"
      )
    )

    expect(submission_group.ext_entities).to contain_exactly(
      have_attributes(
        acc_type: "submission",
        ref_name: "160053",
        status:   "valid"
      ),
      have_attributes(
        acc_type: "submission",
        ref_name: "160053",
        status:   "valid"
      ),
      have_attributes(
        acc_type: "submission",
        ref_name: "160053",
        status:   "valid"
      ),
      have_attributes(
        acc_type: "submission",
        ref_name: "160053",
        status:   "valid"
      )
    )

    expect(submission_group.ext_permits).to contain_exactly(
      have_attributes(
        submitter_id: "alice"
      ),
      have_attributes(
        submitter_id: "alice"
      ),
      have_attributes(
        submitter_id: "alice"
      ),
      have_attributes(
        submitter_id: "alice"
      )
    )
  end
end
