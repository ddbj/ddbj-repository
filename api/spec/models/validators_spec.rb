require 'rails_helper'

RSpec.describe Validators, type: :model do
  let(:validation) {
    create(:validation, db: 'BioProject') {|validation|
      create :obj, validation:, _id: 'BioProject', file: uploaded_file(name: 'mybioproject.xml')
    }
  }

  let(:validator) { double(:validator) }

  before do
    allow(DdbjValidator).to receive(:new) { validator }
  end

  example 'cancel validation' do
    allow(validator).to receive(:validate) {
      validation.update! status: 'canceled', finished_at: '2024-01-02 03:04:56'
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      status:      'canceled',
      validity:    nil,
      finished_at: Time.zone.parse('2024-01-02 03:04:56')
    )
  end

  example 'if error occured during validation, validity is error' do
    allow(validator).to receive(:validate).and_raise(StandardError.new('something went wrong'))

    expect_any_instance_of(ErrorSubscriber).to receive(:report)

    Validators.validate validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'error'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'error',

        details: {
          'error' => 'something went wrong'
        }
      },
      {
        object_id: 'BioProject',
        path:      'mybioproject.xml',
        validity:  nil,
        details:   nil
      }
    )
  end
end
