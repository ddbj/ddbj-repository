require 'rails_helper'

RSpec.describe ValidateJob, type: :job do
  example do
    request = create(:request, db: 'MetaboBank') {|request|
      create :obj, request:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, request:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
    }

    ValidateJob.perform_now request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )
  end
end
