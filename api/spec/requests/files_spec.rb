require 'rails_helper'

RSpec.describe 'download submission files', type: :request, authorized: true do
  before_all do
    user = create(:user, api_key: 'API_KEY')

    create :validation, :valid, id: 100, user:, db: 'JVar' do |validation|
      create :obj, validation:, _id: 'Excel', file: uploaded_file(name: 'myexcel.xlsx'), destination: 'dest', validity: 'valid'
      create :submission, validation:, id: 200, created_at: '2023-12-05'
    end
  end

  example 'from validation' do
    get '/api/validations/100/files/dest%2Fmyexcel.xlsx'

    expect(response).to conform_schema(302)
    expect(response).to redirect_to(%r(\Ahttp://www.example.com/rails/active_storage/disk/))
  end

  example 'from validation, not found' do
    with_exceptions_app do
      get '/api/validations/100/files/foo'
    end

    expect(response).to have_http_status(:not_found)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'not_found'
    )
  end
end
