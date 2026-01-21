require 'rails_helper'

RSpec.describe '/api/api_key', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'regenerate' do
    allow(User).to receive(:generate_api_key) { 'NEW_API_KEY' }

    post '/api/api_key/regenerate'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      api_key: 'NEW_API_KEY'
    )

    expect(user.reload).to have_attributes(
      api_key: 'NEW_API_KEY'
    )
  end
end
