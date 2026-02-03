require 'rails_helper'

RSpec.describe '/api/submission_requests/:submission_request_id/submission', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'create' do
    request = create(:submission_request, :ready_to_apply, user:)

    create :validation, :valid, subject: request

    perform_enqueued_jobs do
      post submission_request_submission_path(request)
    end

    expect(response).to conform_schema(202)
  end
end
