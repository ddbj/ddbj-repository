require "rails_helper"

RSpec.describe Database::BioSample::Validator, type: :model do
  let(:validation) {
    create(:validation, id: 42, db: "BioSample") { |validation|
      create :obj, validation:, _id: "BioSample", file: uploaded_file(name: "mybiosample.xml")
    }
  }

  example "valid" do
    stub_request(:post, "validator.example.com/api/validation").to_return_json(
      body: {
        status: "accepted",
        uuid:   "deadbeef"
      }
    )

    stub_request(:get, "validator.example.com/api/validation/deadbeef/status").to_return_json(
      {
        body: { status: "accepted" }
      },
      {
        body: { status: "running" }
      },
      {
        body: { status: "finished" }
      }
    )

    stub_request(:get, "validator.example.com/api/validation/deadbeef").to_return_json(
      body: {
        result: {
          validity: true,

          messages: [
            id:      "0001",
            level:   "error",
            message: "something went wrong"
          ]
        }
      }
    )

    Database::BioSample::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      {
        object_id: "_base",
        validity:  nil,
        details:   [],
        file:      nil
      },
      {
        object_id: "BioSample",
        validity:  "valid",

        details: [
          code:     "0001",
          severity: "error",
          message:  "something went wrong"
        ],

        file: {
          path: "mybiosample.xml",
          url:  "http://www.example.com/api/validations/42/files/mybiosample.xml"
        }
      }
    )

    expect(a_request(:post, "validator.example.com/api/validation")).to have_been_made.times(1)
    expect(a_request(:get, "validator.example.com/api/validation/deadbeef/status")).to have_been_made.times(3)
    expect(a_request(:get, "validator.example.com/api/validation/deadbeef")).to have_been_made.times(1)
  end

  example "if validation error returned from ddbj_validator, validity is error" do
    stub_request(:post, "validator.example.com/api/validation").to_return_json(
      body: {
        status: "accepted",
        uuid:   "deadbeef"
      }
    )

    stub_request(:get, "validator.example.com/api/validation/deadbeef/status").to_return_json(
      body: {
        status: "error"
      }
    )

    stub_request(:get, "validator.example.com/api/validation/deadbeef").to_return_json(
      body: {
        message: "something went wrong"
      }
    )

    Database::BioSample::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: "_base",
        validity:  nil,
      ),
      include(
        object_id: "BioSample",
        validity:  "error",

        details: [
          code:     nil,
          severity: "error",
          message:  "something went wrong"
        ]
      )
    )
  end

  example "if server error returned from ddbj_validator, validity is error" do
    stub_request(:post, "validator.example.com/api/validation").to_return(
      status: 500,
      body:   "something went wrong"
    )

    Database::BioSample::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: "_base",
        validity:  nil,
      ),
      include(
        object_id: "BioSample",
        validity:  "error",

        details: [
          code:     nil,
          severity: "error",
          message:  "500 Internal Server Error: something went wrong"
        ]
      )
    )
  end
end
