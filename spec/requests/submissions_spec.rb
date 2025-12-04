require 'rails_helper'

RSpec.describe '/api/submissions', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'create' do
    request = create(:submission_request, user:)

    create :validation, :valid, subject: request

    perform_enqueued_jobs do
      post submission_request_submission_path(request), params: {
        submission: {
          visibility: 'public'
        }
      }
    end

    expect(response).to have_http_status(:created)
  end
end
