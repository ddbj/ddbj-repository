require 'rails_helper'

RSpec.describe '/api/submissions', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'index' do
    submission1 = create(:submission, user:)
    submission2 = create(:submission, user:)

    get submissions_path

    expect(response).to conform_schema(200)

    expect(response.parsed_body).to contain_exactly(
      include(id: submission1.id),
      include(id: submission2.id)
    )
  end

  example 'show' do
    submission = create(:submission, user:)

    get submission_path(submission)

    expect(response).to conform_schema(200)

    expect(response.parsed_body).to include(
      id: submission.id
    )
  end
end
