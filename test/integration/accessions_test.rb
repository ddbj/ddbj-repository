require 'test_helper'

class AccessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show' do
    submission = submissions(:one)

    attach_submission_files submission
    attach_ddbj_record submission_updates(:one)

    accession = submission.accessions.first

    get accession_path(accession.number)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal accession.number, body['number']
    assert_equal submission.id,    body.dig('submission', 'id')
    assert_not_nil                 body.dig('submission', 'flatfile_na', 'url')
  end

  test 'show returns 404 for unknown accession' do
    with_exceptions_app do
      get accession_path('UNKNOWN')
    end

    assert_conform_schema 404
  end

  test 'show returns 404 for accession owned by another user' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get accession_path(submissions(:one).accessions.first.number)
    end

    assert_conform_schema 404
  end
end
