require "rails_helper"

RSpec.describe "API key", type: :request do
  describe "GET /api/api_key" do
    example do
      get "/api/api_key"

      expect(response).to conform_schema(200)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        login_url: "http://www.example.com/auth/login"
      )
    end
  end

  describe "POST /api/api_key/regenerate", authorized: true do
    let!(:user) { create(:user, api_key: "API_KEY") }

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
