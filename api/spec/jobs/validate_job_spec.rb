require 'rails_helper'

RSpec.describe ValidateJob, type: :job do
  example do
    validation = create(:validation, db: 'MetaboBank') {|validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
    }

    ValidateJob.perform_now validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )
  end
end
