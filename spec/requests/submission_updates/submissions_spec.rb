require 'rails_helper'

RSpec.describe '/api/submission_updates/:submission_update_id/submission', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'create' do
    update = create(:submission_update, user:)

    create :validation, :valid, subject: update

    perform_enqueued_jobs do
      patch submission_update_submission_path(update)
    end

    expect(response).to conform_schema(202)
  end
end
