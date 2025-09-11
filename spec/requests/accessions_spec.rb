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
    let(:submission) { create(:submission) }

    before do
      create :obj, validation: submission.validation, _id: 'DDBJRecord', file: fixture_file_upload('ddbj_record/example.json')
    end

    example 'ok' do
      accession = create(:accession, entry_id: 'ENTRY_1', submission:)

      patch "/api/accessions/#{accession.number}", params: {
        DDBJRecord: fixture_file_upload('ddbj_record/example.json')
      }

      expect(response).to have_http_status(:ok)
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
