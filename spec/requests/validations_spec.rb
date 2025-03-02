require "rails_helper"

RSpec.describe "vaidations", type: :request, authorized: true do
  let_it_be(:user) { create_default(:user, uid: "alice", api_key: "API_KEY") }

  describe "GET /validations" do
    before do
      travel_to "2024-01-02"

      create :validation, :valid, id: 100, db: "GEA", created_at: "2024-01-02 03:04:56", started_at: "2024-01-02 03:04:57", finished_at: "2024-01-02 03:04:58" do |validation|
        create :submission, validation:, id: 200

        create :obj, validation:, _id: "IDF", file: uploaded_file(name: "myidf.txt"), validity: "valid"
      end

      create :validation, id: 101, db: "MetaboBank", created_at: "2024-01-02 03:04:58", progress: "waiting"
    end

    example do
      get "/api/validations"

      expect(response).to conform_schema(200)

      expect(response.parsed_body.map(&:deep_symbolize_keys)).to eq([
        {
          id:  101,
          url: "http://www.example.com/api/validations/101",

          user: {
            uid: "alice"
          },

          db:          "MetaboBank",
          created_at:  "2024-01-02T03:04:58.000+09:00",
          started_at:  nil,
          finished_at: nil,
          progress:    "waiting",
          validity:    nil,
          objects:     [],

          results: [
            {
              object_id: "_base",
              validity:  nil,
              details:   [],
              file:      nil
            }
          ],

          raw_result: nil,
          submission:  nil
        },
        {
          id:  100,
          url: "http://www.example.com/api/validations/100",

          user: {
            uid: "alice"
          },

          db:          "GEA",
          created_at:  "2024-01-02T03:04:56.000+09:00",
          started_at:  "2024-01-02T03:04:57.000+09:00",
          finished_at: "2024-01-02T03:04:58.000+09:00",
          progress:    "finished",
          validity:    "valid",

          objects: [
            id: "IDF",

            files: [
              path: "myidf.txt",
              url:  "http://www.example.com/api/validations/100/files/myidf.txt"
            ]
          ],

          results: [
            {
              object_id: "_base",
              validity:  "valid",
              details:   [],
              file:      nil
            },
            {
              object_id: "IDF",
              validity:  "valid",
              details:   [],

              file: {
                path: "myidf.txt",
                url:  "http://www.example.com/api/validations/100/files/myidf.txt"
              }
            }
          ],

          raw_result: nil,

          submission: {
            id:  "X-200",
            url: "http://www.example.com/api/submissions/X-200"
          }
        }
      ])
    end
  end

  describe "GET /api/validations/:id" do
    before do
      travel_to "2024-01-02"

      create :validation, :valid, id: 100, db: "BioSample", created_at: "2024-01-02 03:04:56", started_at: "2024-01-02 03:04:57", finished_at: "2024-01-02 03:04:58" do |validation|
        create :submission, validation:, id: 200
      end
    end

    example do
      get "/api/validations/100"

      expect(response).to conform_schema(200)

      expect(response.parsed_body.deep_symbolize_keys).to eq(
        id:  100,
        url: "http://www.example.com/api/validations/100",

        user: {
          uid: "alice"
        },

        db:          "BioSample",
        created_at:  "2024-01-02T03:04:56.000+09:00",
        started_at:  "2024-01-02T03:04:57.000+09:00",
        finished_at: "2024-01-02T03:04:58.000+09:00",
        progress:    "finished",
        validity:    "valid",
        objects:     [],

        results: [
          {
            object_id: "_base",
            validity:  "valid",
            details:   [],
            file:      nil
          }
        ],

        raw_result: nil,

        submission: {
          id:  "X-200",
          url: "http://www.example.com/api/submissions/X-200"
        }
      )
    end
  end

  describe "DELETE /api/validations/:id" do
    before do
      create :validation, id: 100, progress: "waiting"
      create :validation, id: 101, progress: "finished", finished_at: Time.current
    end

    example "if validation is waiting" do
      delete "/api/validations/100"

      expect(response).to conform_schema(200)
    end

    example "if validation is finished" do
      delete "/api/validations/101"

      expect(response).to conform_schema(422)
    end
  end
end
