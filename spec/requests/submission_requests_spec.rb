require 'rails_helper'

RSpec.describe '/submission_requests', type: :request do
  let(:user)            { create(:user) }
  let(:default_headers) { {'Authorization' => "Bearer #{user.api_key}"} }

  example 'index' do
    get submission_requests_path

    expect(response).to have_http_status(:ok)
  end

  example 'show' do
    request = create(:submission_request, user:)

    get submission_request_path(request)

    expect(response).to have_http_status(:ok)

    expect(response.parsed_body).to include(
      objs: contain_exactly(
        include(
          _id: '_base'
        )
      ),

      validation: nil,
      submission: nil
    )
  end

  example 'create' do
    perform_enqueued_jobs do
      post submission_requests_path, params: {
        submission_request: {
          db: 'JVar',

          objs: [
            {
              _id: 'Excel',
              file: uploaded_file(name: 'test.xlsx')
            }
          ]
        }
      }
    end

    expect(response).to have_http_status(:created)

    expect(response.parsed_body).to include(
      objs: contain_exactly(
        include(
          _id:      '_base',
          validity: 'valid',
        ),
        include(
          _id:         'Excel',
          destination: nil,
          validity:    'valid',
          file_url:    a_string_matching(/test\.xlsx$/)
        )
      ),

      validation: include(
        progress: 'finished',
        validity: 'valid',
        details:  []
      ),

      submission: nil
    )
  end
end
