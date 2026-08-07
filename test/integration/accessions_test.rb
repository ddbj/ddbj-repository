require 'test_helper'

class AccessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show' do
    submission = submissions(:st26)

    attach_submission_files submission

    accession = submission.entries.first

    get accession_path(accession.accession)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal accession.accession, body['accession']
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
      get accession_path(submissions(:st26).entries.first.accession)
    end

    assert_conform_schema 404
  end

  # ddbj/submission-bulk-st26 builds the live list from this, and a
  # retracted entry has to be leavable out of it. Without the status the
  # list keeps an entry the flatfile has already dropped.
  test 'the status says whether the entry is still part of the submission' do
    submission = submissions(:st26)
    entry      = submission.entries.first

    attach_submission_files submission
    entry.update!(status: :withdrawn)

    get accession_path(entry.accession)

    assert_conform_schema 200
    assert_equal 'withdrawn', response.parsed_body['status']

    get submission_accessions_path(submission)

    assert_conform_schema 200

    row = response.parsed_body.find { it['accession'] == entry.accession }

    assert_equal 'withdrawn', row['status']
  end
end
