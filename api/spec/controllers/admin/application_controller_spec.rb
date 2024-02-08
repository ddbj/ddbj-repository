require 'rails_helper'

RSpec.describe Admin::ApplicationController, type: :controller do
  controller do
    def index
      render plain: 'hello'
    end
  end

  example 'Forbidden for non-admin user' do
    create :user, api_key: 'API_KEY'

    request.headers['Authorization'] = 'Bearer API_KEY'

    get :index

    expect(response).to have_http_status(403)
    expect(response.parsed_body).to eq('error' => 'Forbidden')
  end
end
