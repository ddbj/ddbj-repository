require 'rails_helper'

RSpec.describe 'me', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, uid: 'alice', api_key: 'API_KEY') }

  before do
    default_headers[:Authorization] = "Bearer #{user.token}"
  end

  example do
    get '/api/me'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      uid:     'alice',
      api_key: 'API_KEY',
      admin:   false
    )
  end
end
