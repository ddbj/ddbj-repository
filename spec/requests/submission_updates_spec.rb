require 'rails_helper'

RSpec.describe '/api/submission_updates', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'show' do
    update = create(:submission_update, user:)

    get submission_update_path(update)

    expect(response).to conform_schema(200)
  end
end
