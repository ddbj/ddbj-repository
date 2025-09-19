require 'rails_helper'

RSpec.describe Database::Trad::DDBJRecordValidator, type: :model do
  example 'invalid file' do
    validation = create(:validation, db: 'Trad', via: :ddbj_record)
    obj        = create(:obj, validation:, _id: 'DDBJRecord', file: uploaded_file(name: 'foo.txt'))

    Database::Trad::DDBJRecordValidator.new.validate validation

    validation.reload

    expect(validation.validity).to eq('invalid')

    expect(obj.validation_details).to include(
      have_attributes(
        severity: 'error',
        message:  'unexpected end of input at line 1 column 1'
      )
    )
  end
end
