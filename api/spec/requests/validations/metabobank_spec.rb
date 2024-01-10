require 'rails_helper'

RSpec.describe 'MetaboBank: submit via file', type: :request, authorized: true do
  before do
    create :user, api_key: 'API_KEY'
  end

  example 'happy case' do
    post '/api/validations/metabobank/via-file', params: {
      IDF:  {file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')},
      SDRF: {file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')}
    }

    expect(response).to conform_schema(201)
    expect(ValidateJob).to have_been_enqueued
  end

  example 'no required parameters' do
    with_exceptions_app do
      post '/api/validations/metabobank/via-file', params: {
        IDF: {file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')}
      }
    end

    expect(response).to have_http_status(:bad_request)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'param is missing or the value is empty: SDRF'
    )

    expect(ValidateJob).not_to have_been_enqueued
  end
end
