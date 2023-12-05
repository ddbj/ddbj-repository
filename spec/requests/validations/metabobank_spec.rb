require 'rails_helper'

RSpec.describe 'MetaboBank: submit via file', type: :request, authorized: true do
  before do
    create :dway_user, api_key: 'API_KEY'
  end

  example do
    post '/api/validations/metabobank/via-file', params: {
      IDF:  {file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')},
      SDRF: {file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')}
    }

    expect(response).to have_http_status(:created)
    expect(ValidateJob).to have_been_enqueued
  end
end