require 'rails_helper'

RSpec.describe 'validations', type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, api_key: 'API_KEY') }

  describe 'GET /api/validations' do
    describe 'payload' do
      before do
        travel_to '2024-01-02'

        create :validation, :valid, id: 100, db: 'GEA', created_at: '2024-01-02 03:04:56', finished_at: '2024-01-02 03:04:57' do |validation|
          create :submission, validation:, id: 200

          create :obj, validation:, _id: 'IDF', file: uploaded_file(name: 'myidf.txt'), validity: 'valid'
        end

        create :validation, id: 101, db: 'MetaboBank', progress: 'waiting', created_at: '2024-01-02 03:04:58'
      end

      example do
        get '/api/validations'

        expect(response).to conform_schema(200)

        expect(response.parsed_body.map(&:deep_symbolize_keys)).to eq([
          {
            id:          101,
            url:         'http://www.example.com/api/validations/101',
            created_at:  '2024-01-02T03:04:58.000Z',
            finished_at: nil,
            db:          'MetaboBank',
            objects:     [],
            progress:    'waiting',
            validity:    nil,

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
            id:          100,
            url:         'http://www.example.com/api/validations/100',
            created_at:  '2024-01-02T03:04:56.000Z',
            finished_at: '2024-01-02T03:04:57.000Z',
            db:          'GEA',

            objects: [
              id: 'IDF',

              files: [
                path: 'myidf.txt',
                url:  'http://www.example.com/api/validations/100/files/myidf.txt'
              ]
            ],

            progress: 'finished',
            validity: 'valid',

            validation_reports: [
              {
                object_id: '_base',
                path:      nil,
                validity:  'valid',
                details:   nil
              },
              {
                object_id: 'IDF',
                path:      'myidf.txt',
                validity:  'valid',
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
          create :validation, id: 100
          create :validation, id: 101
          create :validation, id: 102
          create :validation, id: 103
          create :validation, id: 104
        end

        before do
          stub_const 'Pagy::DEFAULT', Pagy::DEFAULT.merge(items: 2)
        end

        example 'page=1' do
          get '/api/validations'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([104, 103])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/validations?page=1>; rel="first"',
            '<http://www.example.com/api/validations?page=3>; rel="last"',
            '<http://www.example.com/api/validations?page=2>; rel="next"'
          )
        end

        example 'page=2' do
          get '/api/validations?page=2'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([102, 101])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/validations?page=1>; rel="first"',
            '<http://www.example.com/api/validations?page=3>; rel="last"',
            '<http://www.example.com/api/validations?page=1>; rel="prev"',
            '<http://www.example.com/api/validations?page=3>; rel="next"'
          )
        end

        example 'page=3' do
          get '/api/validations?page=3'

          expect(response).to conform_schema(200)
          expect(response.parsed_body.map { _1['id'] }).to eq([100])

          expect(response.headers['Link'].split(/,\s*/)).to contain_exactly(
            '<http://www.example.com/api/validations?page=1>; rel="first"',
            '<http://www.example.com/api/validations?page=3>; rel="last"',
            '<http://www.example.com/api/validations?page=2>; rel="prev"'
          )
        end

        example 'out of range' do
          get '/api/validations?page=4'

          expect(response).to conform_schema(400)

          expect(response.parsed_body.deep_symbolize_keys).to eq(
            error: 'expected :page in 1..3; got 4'
          )
        end
      end

      context 'single page' do
        before_all do
          create :validation, id: 100
        end

        example do
          get '/api/validations'

          expect(response).to have_http_status(200)
          expect(response.headers['Link']).to be_nil
        end
      end
    end
  end

  describe 'GET /api/validations/:id' do
    before do
      travel_to '2024-01-02'

      create :validation, :valid, id: 100, db: 'BioSample', created_at: '2024-01-02 03:04:56', finished_at: '2024-01-02 03:04:57' do |validation|
        create :submission, validation:, id: 200
      end
    end

    example do
      get '/api/validations/100'

      expect(response).to conform_schema(200)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        id:          100,
        url:         'http://www.example.com/api/validations/100',
        created_at:  '2024-01-02T03:04:56.000Z',
        finished_at: '2024-01-02T03:04:57.000Z',
        db:          'BioSample',
        objects:     [],
        progress:    'finished',
        validity:    'valid',

        validation_reports: [
          {
            object_id: '_base',
            path:      nil,
            validity:  'valid',
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

  describe 'DELETE /api/validations/:id' do
    before do
      create :validation, id: 100, progress: 'waiting'
      create :validation, id: 101, progress: 'finished', finished_at: Time.current
    end

    example 'if validation is waiting' do
      delete '/api/validations/100'

      expect(response).to conform_schema(200)
    end

    example 'if validation is finished' do
      delete '/api/validations/101'

      expect(response).to conform_schema(409)
    end
  end
end
