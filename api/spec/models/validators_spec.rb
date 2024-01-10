require 'rails_helper'

RSpec.describe Validators, type: :model do
  let(:request) {
    create(:request, db: 'BioProject') {|request|
      create :obj, request:, _id: 'BioProject', file: uploaded_file(name: 'mybioproject.xml')
    }
  }

  let(:validator) { double(:validator) }

  before do
    allow(DdbjValidator).to receive(:new) { validator }
  end

  example 'cancel request' do
    allow(validator).to receive(:validate) { request.canceled! }

    on_finish_called = false

    Validators.validate request do
      on_finish_called = true
    end

    expect(request).to have_attributes(
      status:   'canceled',
      validity: nil
    )

    expect(on_finish_called).to eq(false)
  end

  example 'if error occured during validation, validity is error' do
    allow(validator).to receive(:validate).and_raise(StandardError.new('something went wrong'))

    expect_any_instance_of(ErrorSubscriber).to receive(:report)

    Validators.validate request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'error'
    )

    expect(request.validation_reports).to contain_exactly(
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
