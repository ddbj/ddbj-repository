require 'rails_helper'

RSpec.describe Database::DRA::Submitter, type: :model do
  example do
    submission   = create(:submission)
    submitter_db = Sequel.connect(ENV.fetch('SUBMITTER_DB_DATABASE_URL'))

    user_id = submitter_db[:login].insert(
      submitter_id: submission.validation.user.uid,
      password:     'password',
    )

    expect(Net::SSH).to receive(:start)

    Database::DRA::Submitter.new.submit submission

    drmdb = Sequel.connect(ENV.fetch('DRMDB_DATABASE_URL'))

    expect(drmdb[:submission].first).to include(usr_id: user_id, submitter_id: submission.validation.user.uid, serial: 1)

    pp drmdb[:status_history]
  end
end
