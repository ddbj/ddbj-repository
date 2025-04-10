require "rails_helper"

RSpec.describe "API key", type: :request do
  let_it_be(:user) { create(:user, api_key: "API_KEY") }

  before do
    default_headers[:Authorization] = "Bearer API_KEY"
  end

  describe "POST /api/api_key/regenerate", authorized: true do
    before do
      allow(User).to receive(:generate_api_key) { "NEW_API_KEY" }
    end

    example do
      post "/api/api_key/regenerate"

      expect(response).to conform_schema(200)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        api_key: "NEW_API_KEY"
      )

      expect(user.reload).to have_attributes(
        api_key: "NEW_API_KEY"
      )
    end
  end
end
