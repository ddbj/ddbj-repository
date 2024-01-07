require 'rails_helper'

RSpec.describe 'requests', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, api_key: 'API_KEY') }

  describe 'GET /api/requests' do
    describe 'payload' do
      before do
        create :request, id: 100, purpose: 'submit', db: 'GEA', status: 'finished' do |request|
          create :submission, request:, id: 200

          create :obj, request:, _id: 'IDF', file: uploaded_file(name: 'myidf.txt')
        end

        create :request, id: 101, purpose: 'submit', db: 'MetaboBank', status: 'waiting'
      end

      example do
        get '/api/requests'

        expect(response).to conform_schema(200)

        expect(response.parsed_body.map(&:deep_symbolize_keys)).to match([
          {
            id:         101,
            url:        'http://www.example.com/api/requests/101',
            created_at: instance_of(String),
            purpose:    'submit',
            db:         'MetaboBank',
            objects:    [],
            status:     'waiting',
            validity:   nil,

            validation_reports: [
              {
                object_id: '_base',
                path:      nil,
                validity:  nil,
                details:   nil
              }
            ],

            submission: nil
          },
          {
            id:         100,
            url:        'http://www.example.com/api/requests/100',
            created_at: instance_of(String),
            purpose:    'submit',
            db:         'GEA',

            objects: [
              id: 'IDF',

              files: [
                path: 'myidf.txt',
                url:  'http://www.example.com/api/requests/100/files/myidf.txt'
              ]
            ],

            status:   'finished',
            validity: nil,

            validation_reports: [
              {
                object_id: '_base',
                path:      nil,
                validity:  nil,
                details:   nil
              },
              {
                object_id: 'IDF',
                path:      'myidf.txt',
                validity:  nil,
                details:   nil
              },
            ],

            submission: {
              id:  'X-200',
              url: 'http://www.example.com/api/submissions/X-200'
            }
          }
        ])
      end
    end

    describe 'pagination' do
      context 'paginated' do
        before_all do
          create :request, id: 100
          create :request, id: 101
          create :request, id: 102
          create :request, id: 103
          create :request, id: 104
        end

        before do
          stub_const 'Pagy::DEFAULT', Pagy::DEFAULT.merge(items: 2)
        end

        example 'page=1' do
          get '/api/requests'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([104, 103])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/requests?page=1>; rel="first"',
            '<http://www.example.com/api/requests?page=3>; rel="last"',
            '<http://www.example.com/api/requests?page=2>; rel="next"'
          )
        end

        example 'page=2' do
          get '/api/requests?page=2'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([102, 101])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/requests?page=1>; rel="first"',
            '<http://www.example.com/api/requests?page=3>; rel="last"',
            '<http://www.example.com/api/requests?page=1>; rel="prev"',
            '<http://www.example.com/api/requests?page=3>; rel="next"'
          )
        end

        example 'page=3' do
          get '/api/requests?page=3'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([100])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/requests?page=1>; rel="first"',
            '<http://www.example.com/api/requests?page=3>; rel="last"',
            '<http://www.example.com/api/requests?page=2>; rel="prev"'
          )
        end

        example 'out of range' do
          get '/api/requests?page=4'

          expect(response).to conform_schema(400)

          expect(response.parsed_body.deep_symbolize_keys).to eq(
            error: 'expected :page in 1..3; got 4'
          )
        end
      end

      context 'single page' do
        before_all do
          create :request, id: 100
        end

        example do
          get '/api/requests'

          expect(response).to conform_schema(200)
          expect(response.headers['Link']).to be_nil
        end
      end
    end
  end

  describe 'GET /api/requests/:id' do
    before do
      create :request, id: 100, purpose: 'submit', db: 'BioSample', status: 'finished' do |request|
        create :submission, request:, id: 200
      end
    end

    example do
      get '/api/requests/100'

      expect(response).to conform_schema(200)

      expect(response.parsed_body.deep_symbolize_keys).to match(
        id:         100,
        url:        'http://www.example.com/api/requests/100',
        created_at: instance_of(String),
        purpose:    'submit',
        db:         'BioSample',
        objects:    [],
        status:     'finished',
        validity:   nil,

        validation_reports: [
          {
            object_id: '_base',
            path:      nil,
            validity:  nil,
            details:   nil
          }
        ],

        submission: {
          id:  'X-200',
          url: 'http://www.example.com/api/submissions/X-200'
        }
      )
    end
  end

  describe 'DELETE /api/requests/:id' do
    before do
      create :request, id: 100, status: 'waiting'
      create :request, id: 101, status: 'finished'
    end

    example 'if request is waiting' do
      delete '/api/requests/100'

      expect(response).to conform_schema(200)
    end

    example 'if request is finished' do
      delete '/api/requests/101'

      expect(response).to conform_schema(409)
    end
  end
end
