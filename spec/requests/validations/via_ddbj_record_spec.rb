require 'rails_helper'

RSpec.describe 'validate via DDBJRecord', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, uid: 'alice') }

  before do
    default_headers[:Authorization] = "Bearer #{user.token}"
  end

  example 'happy case' do
    post '/api/validations/via_ddbj_record', params: {
      db: 'Trad',

      DDBJRecord: {
        file: uploaded_file(name: 'JP2022130675.json')
      }
    }

    expect(response).to have_http_status(:created)
  end
end
