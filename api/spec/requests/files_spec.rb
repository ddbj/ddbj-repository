require 'rails_helper'

RSpec.describe 'download submission files', type: :request, authorized: true do
  before_all do
    user = create(:user, api_key: 'API_KEY')

    create :request, id: 100, user:, db: 'JVar' do |request|
      create :obj, request:, _id: 'Excel', file: uploaded_file(name: 'myexcel.xlsx'), destination: 'dest'
      create :submission, request:, id: 200, created_at: '2023-12-05'
    end
  end

  example 'from request' do
    get '/api/requests/100/files/dest%2Fmyexcel.xlsx'

    expect(response).to conform_schema(302)
    expect(response).to redirect_to(%r(\Ahttp://www.example.com/rails/active_storage/disk/))
  end

  example 'from request, not found' do
    with_exceptions_app do
      get '/api/requests/100/files/foo'
    end

    expect(response).to have_http_status(:not_found)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'not_found'
    )
  end

  example 'from submission' do
    get '/api/submissions/X-200/files/dest%2Fmyexcel.xlsx'

    expect(response).to conform_schema(302)
    expect(response).to redirect_to(%r(\Ahttp://www.example.com/rails/active_storage/disk/))
  end

  example 'from submission, not found' do
    with_exceptions_app do
      get '/api/submissions/X-200/files/foo'
    end

    expect(response).to have_http_status(:not_found)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'not_found'
    )
  end
end
