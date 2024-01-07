require 'rails_helper'

RSpec.describe 'submissions', type: :request, authorized: true do
  before do
    user = create(:user, api_key: 'API_KEY')

    create :request, user:, db: 'JVar' do |request|
      create :obj, request:, _id: 'Excel', file: uploaded_file(name: 'myexcel.xlsx'), destination: 'dest'
      create :submission, request:, id: 42, created_at: '2023-12-05'
    end
  end

  example 'GET /api/submissions' do
    get '/api/submissions'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.map(&:deep_symbolize_keys)).to eq([
      {
        id:         'X-42',
        url:        'http://www.example.com/api/submissions/X-42',
        created_at: '2023-12-05T00:00:00.000Z',
        db:         'JVar',

        objects: [
          id: 'Excel',

          files: [
            path: 'dest/myexcel.xlsx',
            url:  'http://www.example.com/api/submissions/X-42/files/dest/myexcel.xlsx'
          ]
        ]
      }
    ])
  end

  example 'GET /api/submissions/:id' do
    get '/api/submissions/X-42'

    expect(response).to conform_schema(200)

    expect(response.parsed_body.deep_symbolize_keys).to eq(
      id:         'X-42',
      url:        'http://www.example.com/api/submissions/X-42',
      created_at: '2023-12-05T00:00:00.000Z',
      db:         'JVar',

      objects: [
        id: 'Excel',

        files: [
          path: 'dest/myexcel.xlsx',
          url:  'http://www.example.com/api/submissions/X-42/files/dest/myexcel.xlsx'
        ]
      ]
    )
  end
end
