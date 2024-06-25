require 'rails_helper'

RSpec.describe ValidateJob, type: :job do
  let(:validation) {
    create(:validation, id: 42, db: 'BioProject') {|validation|
      create :obj, validation:, _id: 'BioProject', file: uploaded_file(name: 'mybioproject.xml')
    }
  }

  let(:validator) { double(:validator) }

  before do
    allow(DDBJValidator).to receive(:new) { validator }
  end

  example 'valid' do
    allow(validator).to receive(:validate) {
      validation.reload.objs.each &:validity_valid!
    }

    ValidateJob.perform_now validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'valid'
    )
  end

  example 'cancel validation' do
    allow(validator).to receive(:validate) {
      validation.update! progress: 'canceled', finished_at: '2024-01-02 03:04:56'
    }

    ValidateJob.perform_now validation

    expect(validation).to have_attributes(
      progress:    'canceled',
      validity:    nil,
      finished_at: Time.zone.parse('2024-01-02 03:04:56')
    )
  end

  example 'if error occured during validation, validity is error' do
    allow(validator).to receive(:validate).and_raise(StandardError.new('something went wrong'))

    expect_any_instance_of(ErrorSubscriber).to receive(:report)

    ValidateJob.perform_now validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'error'
    )

    expect(validation.results).to contain_exactly(
      {
        object_id: '_base',
        validity:  'error',

        details: {
          'error' => 'something went wrong'
        },

        file: nil
      },
      {
        object_id: 'BioProject',
        validity:  nil,
        details:   nil,

        file: {
          path: 'mybioproject.xml',
          url:  'http://www.example.com/api/validations/42/files/mybioproject.xml'
        }
      }
    )
  end
end
