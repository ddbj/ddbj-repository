require 'rails_helper'

RSpec.describe '/api/me', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'show' do
    get '/api/me'

    expect(response).to conform_schema(200)
  end
end
