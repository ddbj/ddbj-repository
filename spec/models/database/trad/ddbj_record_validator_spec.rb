require 'rails_helper'

RSpec.describe Database::Trad::DDBJRecordValidator, type: :model do
  example 'not a JSON' do
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

  example 'invalid' do
    validation = create(:validation, db: 'Trad', via: :ddbj_record)
    obj        = create(:obj, validation:, _id: 'DDBJRecord', file: file_fixture_upload('ddbj_record/invalid.json'))

    Database::Trad::DDBJRecordValidator.new.validate validation

    validation.reload

    expect(validation.validity).to eq('invalid')

    expect(obj.validation_details).to contain_exactly(
      have_attributes(
        entry_id: nil,
        code:     'TRD_R0001',
        severity: 'error',
        message:  'ApplicationNumberText must be in the format of yyyy-nnnnnn'
      ),
      have_attributes(
        entry_id: 'SEQ_1',
        code:     'TRD_R0006',
        severity: 'warning',
        message:  'Undefined feature key "bar"'
      ),
      have_attributes(
        entry_id: 'SEQ_1',
        code:     'TRD_R0007',
        severity: 'warning',
        message:  'Undefined qualifier key "baz" (feature=bar)'
      ),
      have_attributes(
        entry_id: 'SEQ_1',
        code:     'TRD_R0008',
        severity: 'error',
        message:  'Invalid presence of qualifier value for key "baz" (feature=bar)'
      ),
      have_attributes(
        entry_id: 'SEQ_1',
        code:     'TRD_R0002',
        severity: 'error',
        message:  'Sequence length is zero'
      ),
      have_attributes(
        entry_id: 'SEQ_2',
        code:     'TRD_R0003',
        severity: 'error',
        message:  'N-only sequence is not allowed'
      ),
      have_attributes(
        entry_id: 'SEQ_3',
        code:     'TRD_R0004',
        severity: 'error',
        message:  'X-only sequence is not allowed'
      ),
      have_attributes(
        entry_id: 'SEQ_3',
        code:     'TRD_R0007',
        severity: 'warning',
        message:  'Undefined qualifier key "mol_type" (source)'
      ),
      have_attributes(
        entry_id: 'SEQ_4',
        code:     'TRD_R0005',
        severity: 'error',
        message:  'Invalid characters found in nucleotide sequence'
      )
    )
  end
end
