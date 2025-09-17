require 'rails_helper'

RSpec.describe '/api/accessions', type: :request do
  let_it_be(:user) { create_default(:user) }

  before do
    default_headers[:Authorization] = "Bearer #{user.token}"
  end

  example 'show' do
    submission = create(:submission)
    accession  = create(:accession, submission:)

    get "/api/accessions/#{accession.number}"

    expect(response).to conform_schema(200)
  end

  describe 'update' do
    let(:submission) {
      create(:submission, **{
        validation: create(:validation, :valid, db: 'Trad', via: :ddbj_record) {|validation|
          create :obj, :valid, validation:, _id: 'DDBJRecord', file: file_fixture_upload('ddbj_record/example.json')
        }
      })
    }

    example 'ok' do
      SubmitJob.perform_now submission

      submission.reload

      travel_to 1.second.since

      patch "/api/accessions/#{submission.accessions.first.number}", params: {
        DDBJRecord: fixture_file_upload('ddbj_record/example.json')
      }

      expect(response).to have_http_status(:ok)

      submission.reload

      objs = submission.validation.objs.DDBJRecord

      expect(objs.size).to eq(3)

      record = JSON.parse(objs.last.file.download, symbolize_names: true)

      expect(record).to match(
        sequence: {
          entries: include(
            id:           'ENTRY_1',
            accession:    'QP000001',
            locus:        'QP000001',
            version:      2,
            last_updated: be_a(String)
          )
        }
      )
    end

    example 'entry_id did not match' do
      accession = create(:accession, entry_id: 'ENTRY_3', submission:)

      patch "/api/accessions/#{accession.number}", params: {
        DDBJRecord: fixture_file_upload('ddbj_record/example.json')
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
