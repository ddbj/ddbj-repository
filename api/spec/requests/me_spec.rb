require 'rails_helper'

RSpec.describe 'me', type: :request, authorized: true do
  before do
    create :user, uid: 'alice', api_key: 'API_KEY', ddbj_member: false
  end

  example do
    get '/api/me'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      uid:         'alice',
      ddbj_member: false
    )
  end
end
