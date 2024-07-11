require 'rails_helper'

RSpec.describe Database::DRA::Submitter, type: :model do
  example do
    submission = create(:submission, {
      validation: build(:validation, :valid, {
        user: build(:user, uid: 'alice')
      })
    })

    user_id = Dway.submitter_db[:login].insert(
      submitter_id: 'alice',
      password:     'password',
    )

    expect(Net::SSH).to receive(:start)

    Database::DRA::Submitter.new.submit submission

    expect(Dway.drmdb[:submission].count).to eq(1)

    dway_submission = Dway.drmdb[:submission].first
    expect(dway_submission).to include(usr_id: user_id, submitter_id: 'alice', serial: 1)

    expect(Dway.drmdb[:status_history].count).to eq(1)
    
    status_history = Dway.drmdb[:status_history].first
    expect(status_history).to include(sub_id: dway_submission[:sub_id], status: 100)

    expect(Dway.drmdb[:operation_history].count).to eq(1)

    operation_history = Dway.drmdb[:operation_history].first
    expect(operation_history).to include(type: 3, summary: 'Status update to new', usr_id: user_id, serial: 1, submitter_id: 'alice')

    expect(Dway.drmdb[:ext_entity].count).to eq(1)

    ext_entity = Dway.drmdb[:ext_entity].first
    expect(ext_entity).to include(acc_type: 'DRA', ref_name: 'alice-0001', status: 0)

    expect(Dway.drmdb[:ext_permit].count).to eq(1)

    ext_permit = Dway.drmdb[:ext_permit].first
    expect(ext_permit).to include(ext_id: ext_entity[:ext_id], submitter_id: 'alice') 
  end
end
