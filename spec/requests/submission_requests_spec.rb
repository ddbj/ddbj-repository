require 'rails_helper'

RSpec.describe '/api/submission_requests', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'index' do
    get submission_requests_path

    expect(response).to have_http_status(:ok)
  end

  example 'show' do
    request = create(:submission_request, user:)

    get submission_request_path(request)

    expect(response).to have_http_status(:ok)
  end

  example 'create' do
    perform_enqueued_jobs do
      post submission_requests_path, params: {
        submission_request: {
          ddbj_record: fixture_file_upload('ddbj_record/example.json', 'application/json')
        }
      }
    end

    expect(response).to have_http_status(:accepted)

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
