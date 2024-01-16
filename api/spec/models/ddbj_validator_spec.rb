require 'rails_helper'

RSpec.describe DdbjValidator, type: :model do
  let(:validation) {
    create(:validation, db: 'BioSample') {|validation|
      create :obj, validation:, _id: 'BioSample', file: uploaded_file(name: 'mybiosample.xml')
    }
  }

  example do
    stub_request(:post, 'validator.example.com/api/validation').to_return_json(
      body: {
        status: 'accepted',
        uuid:   'deadbeef'
      }
    )

    stub_request(:get, 'validator.example.com/api/validation/deadbeef/status').to_return_json(
      {
        body: {status: 'accepted'}
      },
      {
        body: {status: 'running'}
      },
      {
        body: {status: 'finished'}
      }
    )

    stub_request(:get, 'validator.example.com/api/validation/deadbeef').to_return_json(
      body: {
        result: {
          validity: true,
          answer:   42
        }
      }
    )

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'BioSample',
        path:      'mybiosample.xml',
        validity:  'valid',

        details: {
          'validity' => true,
          'answer'   => 42
        }
      }
    )

    expect(a_request(:post, 'validator.example.com/api/validation')).to have_been_made.times(1)
    expect(a_request(:get, 'validator.example.com/api/validation/deadbeef/status')).to have_been_made.times(3)
    expect(a_request(:get, 'validator.example.com/api/validation/deadbeef')).to have_been_made.times(1)
  end

  example 'if error occured from ddbj_validator, validity is error' do
    stub_request(:post, 'validator.example.com/api/validation').to_return status: 500

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'error'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'BioSample',
        path:      'mybiosample.xml',
        validity:  'error',

        details: {
          'error' => instance_of(String)
        }
      }
    )
  end
end
