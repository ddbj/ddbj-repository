require 'test_helper'

# The four workbench tabs: each renders, each keeps the shared summary
# bar, and each loads only what it shows.
class AdminWorkbenchTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @req = submission_requests(:biosample)
  end

  test 'overview renders the summary bar, progress, tabs and the curation rail' do
    get admin_submission_request_path(@req)

    assert_response :ok
    assert_match "##{@req.id}",                                              response.body
    assert_match 'BioSample',                                                    response.body
    assert_match 'Accession issued',                                             response.body # progress step
    assert_match samples_admin_submission_request_path(@req),                response.body
    assert_match messages_admin_submission_request_path(@req),               response.body
    assert_match record_admin_submission_request_path(@req),                 response.body
    assert_match admin_submission_curation_path(@req.submission),            response.body
  end

  test 'overview of a request with no submission still renders' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    attach_ddbj_record(request)
    request.save!

    get admin_submission_request_path(request)

    assert_response :ok
    assert_no_match admin_submission_curation_path(request.id), response.body
  end

  test 'samples tab lists the submission samples with the bulk bar' do
    get samples_admin_submission_request_path(@req)

    assert_response :ok
    assert_match 'fixture-sample-1',                                          response.body
    assert_match 'fixture-sample-2',                                          response.body
    assert_match bulk_update_samples_admin_submission_path(@req.submission), response.body
    assert_match 'matching the filter',                                       response.body
  end

  test 'samples tab filters by search term' do
    get samples_admin_submission_request_path(@req), params: {q: 'sample-1'}

    assert_response :ok
    assert_match    'fixture-sample-1', response.body
    assert_no_match 'fixture-sample-2', response.body
  end

  test 'samples tab filters by accession state' do
    get samples_admin_submission_request_path(@req), params: {accession: 'not_issued'}

    assert_response :ok
    assert_no_match 'fixture-sample-1', response.body
    assert_match    'fixture-sample-2', response.body
  end

  test 'samples tab redirects to overview for a non-BS request' do
    get samples_admin_submission_request_path(submission_requests(:bioproject))

    assert_redirected_to admin_submission_request_path(submission_requests(:bioproject))
  end

  test 'messages tab renders the thread and marks submitter messages read' do
    message = @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    get messages_admin_submission_request_path(@req)

    assert_response :ok
    assert_match 'Please advise', response.body
    assert_not_nil message.reload.read_at
  end

  test 'overview does not mark messages read' do
    message = @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Still waiting')

    get admin_submission_request_path(@req)

    assert_response :ok
    assert_nil message.reload.read_at
  end

  test 'record tab renders the chain and engineering details' do
    get record_admin_submission_request_path(@req)

    assert_response :ok
    assert_match 'Patch chain',         response.body
    assert_match 'Engineering details', response.body
    assert_match 'Canonical version',   response.body
  end

  test 'workbench requires admin auth' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submission_request_path(@req)
    end

    assert_response :forbidden
  end
end
