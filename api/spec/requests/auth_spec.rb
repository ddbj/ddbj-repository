require 'rails_helper'

RSpec.describe 'authentication', type: :request do
  def userinfo(account_type_number:)
    double(:userinfo, {
      preferred_username: 'alice',
      email:              'alice@exmaple.com',

      raw_attributes: {
        'account_type_number' => account_type_number,
        'given_name'          => 'Alice',
        'sn'                  => 'Liddell',
        'institution'         => 'Wonderland Inc.'
      }
    })
  end

  let(:oidc_client) { spy(:oidc_client) }

  let(:access_token) {
    double(:access_token)
  }

  around do |example|
    ClimateControl.modify OIDC_CLIENT_ID: 'CLIENT_ID', &example
  end

  before do
    allow_any_instance_of(AuthsController).to receive(:oidc_client) { oidc_client }

    allow(User).to receive(:generate_api_key) { 'API_KEY' }
    allow(oidc_client).to receive(:authorization_uri) { 'http://example.com/auth/authorization' }
  end

  describe 'login' do
    before do
      allow_any_instance_of(AuthsController).to receive(:generate_state) { 'STATE' }
      allow_any_instance_of(AuthsController).to receive(:generate_code_verifier) { 'CODE_VERIFIER' }
      allow_any_instance_of(AuthsController).to receive(:calculate_code_challenge).with('CODE_VERIFIER') { 'CODE_CHALLENGE' }

      allow(access_token).to receive(:userinfo!) { userinfo(account_type_number: 1) }
      allow(oidc_client).to receive(:access_token!) { access_token }
    end

    example do
      get '/auth/login'

      expect(response).to redirect_to('http://example.com/auth/authorization')

      expect(oidc_client).to have_received(:authorization_uri).with(
        scope:                 %i(openid ddbj email profile),
        state:                 'STATE',
        code_challenge:        'CODE_CHALLENGE',
        code_challenge_method: 'S256'
      )

      get '/auth/callback', params: {
        state: 'STATE',
        code:  'CODE'
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Your API key is: API_KEY')

      user = User.find_by!(uid: 'alice')

      expect(user).to have_attributes(
        api_key: 'API_KEY',
        admin:   false
      )

      expect(oidc_client).to have_received(:authorization_code=).with('CODE')
      expect(oidc_client).to have_received(:access_token!).with(code_verifier: 'CODE_VERIFIER')
    end
  end
end
