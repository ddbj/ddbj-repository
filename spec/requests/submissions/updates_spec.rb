require 'rails_helper'

RSpec.describe '/api/submissions/:submission_id/updates', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'create' do
    submission = create(:submission, user:)

    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    post submission_updates_path(submission), params: {
      submission_update: {
        ddbj_record: blob.signed_id
      }
    }, as: :json

    expect(response).to conform_schema(202)
  end
end
