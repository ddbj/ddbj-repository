require 'rails_helper'

RSpec.describe 'validate via file', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, uid: 'alice') }

  before do
    default_headers[:Authorization] = "Bearer #{user.token}"
  end

  before do
  end

  example 'happy case' do
    post '/api/validations/via_file', params: {
      db:   'MetaboBank',
      IDF:  {file: file_fixture_upload('metabobank/MTBKS231.idf.txt')},
      SDRF: {file: file_fixture_upload('metabobank/MTBKS231.sdrf.txt')}
    }

    # We are supposed to use `comform_schema` but it does not success.
    expect(response).to have_http_status(201)
    expect(ValidateJob).to have_been_enqueued
  end

  example 'if path does not exist' do
    with_exceptions_app do
      post '/api/validations/via_file', params: {
        db:    'JVar',
        Excel: {path: '_foo'}
      }
    end

    expect(response).to have_http_status(422)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: "path does not exist: #{Rails.root}/spec/fixtures/files/submission/alice/_foo"
    )
  end

  example 'if obj is multiple and path is directory, read recursive' do
    post '/api/validations/via_file', params: {
      db: 'MetaboBank',

      IDF: {
        file: uploaded_file(name: 'myidf.txt')
      },

      SDRF: {
        file: uploaded_file(name: 'mysdrf.txt')
      },

      RawDataFile: {
        path: 'foo'
      },

      ProcessedDataFile: {
        path:        'foo',
        destination: 'dest'
      }
    }

    expect(response).to have_http_status(201)

    validation = Validation.find(response.parsed_body['id'])

    expect(validation.objs.map(&:_id)).to contain_exactly(
      '_base',
      'IDF',
      'SDRF',
      'RawDataFile',
      'RawDataFile',
      'ProcessedDataFile',
      'ProcessedDataFile'
    )

    expect(validation.objs.select { _1._id == 'RawDataFile' }.map(&:path)).to contain_exactly(
      'bar',
      'baz/qux'
    )

    expect(validation.objs.select { _1._id == 'ProcessedDataFile' }.map(&:path)).to contain_exactly(
      'dest/bar',
      'dest/baz/qux'
    )
  end

  example 'if obj is not multiple and path is directory' do
    with_exceptions_app do
      post '/api/validations/via_file', params: {
        db:    'JVar',
        Excel: {path: 'foo'}
      }
    end

    expect(response).to have_http_status(422)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: "path is directory: #{Rails.root}/spec/fixtures/files/submission/alice/foo"
    )
  end

  example 'if path is duplicated' do
    with_exceptions_app do
      post '/api/validations/via_file', params: {
        db:   'MetaboBank',
        IDF:  {file: uploaded_file(name: 'idf.txt')},
        SDRF: {file: uploaded_file(name: 'idf.txt')}
      }
    end

    expect(response).to have_http_status(422)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'Validation failed: Path is duplicated: idf.txt'
    )
  end

  example 'no required parameters' do
    with_exceptions_app do
      post '/api/validations/via_file', params: {
        db:   'MetaboBank',
        IDF: {file: file_fixture_upload('metabobank/MTBKS231.idf.txt')}
      }
    end

    expect(response).to have_http_status(400)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'param is missing or the value is empty or invalid: SDRF'
    )

    expect(ValidateJob).not_to have_been_enqueued
  end

  example 'unknown db' do
    with_exceptions_app do
      post '/api/validations/via_file', params: {
        db: 'foo'
      }
    end

    expect(response).to have_http_status(422)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      error: 'unknown db: foo'
    )
  end
end
