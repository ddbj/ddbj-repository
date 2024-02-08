require 'rails_helper'

RSpec.describe 'admin/validations', type: :request, authorized: true do
  describe 'GET /api/admin/validations' do
    example 'search by uid' do
      create :user, admin: true, api_key: 'API_KEY'

      create :user, uid: 'alice' do |user|
        create :validation, id: 100, user: user
      end

      create :user, uid: 'bob' do |user|
        create :validation, id: 101, user: user
      end

      create :user do |user|
        create :validation, id: 102, user: user
      end

      get '/api/admin/validations', params: {uid: 'alice,bob'}

      expect(response).to have_http_status(200)
      expect(response.parsed_body.map { _1[:id] }).to eq([101, 100])
    end
  end
end
