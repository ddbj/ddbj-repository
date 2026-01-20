require 'rails_helper'

RSpec.describe '/api/submission_requests', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'index' do
    get submission_requests_path

    expect(response).to conform_schema(200)
  end

  example 'show' do
    request = create(:submission_request, user:)

    get submission_request_path(request)

    expect(response).to conform_schema(200)
  end

  example 'create' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post submission_requests_path, params: {
        submission_request: {
          ddbj_record: blob.signed_id
        }
      }, as: :json
    end

    expect(response).to conform_schema(202)

    expect(response.parsed_body).to include(
      validation: include(
        progress: 'finished',
        validity: 'valid',
        details:  []
      ),

      submission: nil
    )
  end
end
