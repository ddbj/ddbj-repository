require 'rails_helper'

RSpec.describe GeaValidator, type: :model do
  example 'valid' do
    validation = create(:validation, id: 42, db: 'GEA') {|validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('gea/valid/E-GEAD-282.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('gea/valid/E-GEAD-282.sdrf.txt')
    }

    GeaValidator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      {
        object_id: '_base',
        validity:  nil,
        details:   nil,
        file:      nil
      },
      {
        object_id: 'IDF',
        validity:  'valid',
        details:   instance_of(Array),

        file: {
          path: 'E-GEAD-282.idf.txt',
          url:  'http://www.example.com/api/validations/42/files/E-GEAD-282.idf.txt'
        }
      },
      {
        object_id: 'SDRF',
        validity:  'valid',
        details:   instance_of(Array),

        file: {
          path: 'E-GEAD-282.sdrf.txt',
          url:  'http://www.example.com/api/validations/42/files/E-GEAD-282.sdrf.txt'
        }
      }
    )
  end
end
