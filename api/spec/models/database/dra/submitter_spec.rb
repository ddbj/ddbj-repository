require 'rails_helper'

RSpec.describe Database::DRA::Submitter, type: :model do
  example do
    submission = create(:submission, {
      validation: build(:validation, :valid, {
        user: build(:user, uid: 'alice')
      })
    })

    user_id = create(:submitterdb_login, **{
      submitter_id: 'alice'
    }).usr_id

    expect(Net::SSH).to receive(:start)

    Database::DRA::Submitter.new.submit submission

    submission = DRMDB::Submission.sole

    expect(submission).to have_attributes(
      usr_id:       user_id,
      submitter_id: 'alice',
      serial:       1
    )

    status_history = DRMDB::StatusHistory.sole

    expect(status_history).to have_attributes(
      sub_id: submission[:sub_id],
      status: 'new'
    )

    operation_history = DRMDB::OperationHistory.sole

    expect(operation_history).to have_attributes(
      type:         'info',
      summary:      'Status update to new',
      usr_id:       user_id,
      serial:       1,
      submitter_id: 'alice'
    )

    ext_entity = DRMDB::ExtEntity.sole

    expect(ext_entity).to have_attributes(
      acc_type: 'submission',
      ref_name: 'alice-0001',
      status:   'inputting'
    )

    ext_permit = DRMDB::ExtPermit.sole

    expect(ext_permit).to have_attributes(
      ext_id:       ext_entity.ext_id,
      submitter_id: 'alice'
    )

    submission_group = DRMDB::SubmissionGroup.sole

    expect(submission_group).to have_attributes(
      submit_version: 1,
      valid:          true,
      serial_version: 1
    )
  end
end
