require 'rails_helper'

RSpec.describe 'submissions', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, uid: 'alice') }

  before do
    default_headers[:Authorization] = "Bearer #{user.token}"
  end

  example 'GET /api/submissions' do
    create :submission, id: 42

    get '/api/submissions'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.map(&:deep_symbolize_keys).map { _1[:id] }).to eq(['X-42'])
  end

  example 'GET /api/submissions/:id' do
    travel_to '2024-01-02'

    create :validation, :valid, id: 100, db: 'JVar', created_at: '2024-01-02 03:04:56', started_at: '2024-01-02 03:04:57', finished_at: '2024-01-02 03:04:58' do |validation|
      create :submission, validation:, id: 200, created_at: '2024-01-02 03:04:58'

      create :obj, validation:, _id: 'Excel', file: uploaded_file(name: 'myexcel.xlsx'), destination: 'dest', validity: 'valid'
    end

    get '/api/submissions/X-200'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      id:            'X-200',
      url:           'http://www.example.com/api/submissions/X-200',
      created_at:    '2024-01-02T03:04:58.000+09:00',
      started_at:    nil,
      finished_at:   nil,
      progress:      'waiting',
      result:        nil,
      error_message: nil,
      accessions:    [],

      validation:    {
        id:          100,
        url:         'http://www.example.com/api/validations/100',

        user:        {
          uid:       'alice'
        },

        db:          'JVar',
        created_at:  '2024-01-02T03:04:56.000+09:00',
        started_at:  '2024-01-02T03:04:57.000+09:00',
        finished_at: '2024-01-02T03:04:58.000+09:00',
        progress:    'finished',
        validity:    'valid',

        objects: [
          id: 'Excel',

          files: [
            path: 'dest/myexcel.xlsx',
            url:  'http://www.example.com/api/validations/100/files/dest/myexcel.xlsx'
          ]
        ],

        results: [
          {
            object_id: '_base',
            validity:  'valid',
            details:   [],
            file:      nil
          },
          {
            object_id: 'Excel',
            validity:  'valid',
            details:   [],

            file: {
              path: 'dest/myexcel.xlsx',
              url:  'http://www.example.com/api/validations/100/files/dest/myexcel.xlsx'
            }
          }
        ],

        raw_result: nil,

        submission: {
          id:  'X-200',
          url: 'http://www.example.com/api/submissions/X-200'
        }
      },

      visibility: 'public'
    )
  end

  describe 'POST /api/submissions' do
    example 'ok' do
      create :validation, :valid, id: 42, db: 'JVar'

      post '/api/submissions', params: {
        db:            'JVar',
        validation_id: 42,
        visibility:    'public'
      }, as: :json

      expect(response).to conform_schema(201)
      expect(response.parsed_body.deep_symbolize_keys.dig(:validation, :id)).to eq(42)
    end

    example 'validity is not valid' do
      create :validation, id: 42, db: 'JVar'

      with_exceptions_app do
        post '/api/submissions', params: {
          db:            'JVar',
          validation_id: 42,
          visibility:    'public'
        }, as: :json
      end

      expect(response).to have_http_status(422)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        error: 'Validation failed: Validation must be valid'
      )
    end

    example 'expired' do
      travel_to '2024-01-03 03:04:56'

      create :validation, :valid, id: 42, db: 'JVar', finished_at: '2024-01-02 03:04:56'

      with_exceptions_app do
        post '/api/submissions', params: {
          db:            'JVar',
          validation_id: 42,
          visibility:    'public'
        }, as: :json
      end

      expect(response).to have_http_status(422)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        error: 'Validation failed: Validation finished_at must be in 24 hours'
      )
    end

    example 'duplicated' do
      create :validation, :valid, id: 42, db: 'JVar' do |validation|
        create :submission, validation:
      end

      with_exceptions_app do
        post '/api/submissions', params: {
          db:            'JVar',
          validation_id: 42,
          visibility:    'public'
        }, as: :json
      end

      expect(response).to have_http_status(422)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        error: 'Validation failed: Validation is already submitted'
      )
    end
  end
end
