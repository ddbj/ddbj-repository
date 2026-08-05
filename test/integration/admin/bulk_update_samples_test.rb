require 'test_helper'

class AdminBulkUpdateSamplesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:biosample)
    @sample_a   = samples(:first)
    @sample_b   = samples(:second)
  end

  test 'bulk_update_samples sets status on every sample in one SQL' do
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'curating'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/Bulk-updated 2 sample/, flash[:notice])

    assert_equal 'curating', @sample_a.reload.status
    assert_equal 'curating', @sample_b.reload.status
  end

  test 'bulk_update_samples with a blank status refuses the no-op' do
    original_a = @sample_a.status

    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: ''}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/No changes specified/, flash[:alert])
    assert_equal original_a, @sample_a.reload.status
  end

  test 'bulk_update_samples rejects unknown status (manual cast guard)' do
    original_a = @sample_a.status
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'nope_not_a_status'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/Unknown status/, flash[:alert])
    assert_equal original_a, @sample_a.reload.status
  end

  test 'bulk_update_samples 404s for non-BS submissions' do
    post bulk_update_samples_admin_submission_path(submissions(:bioproject)),
          params: {bulk_sample: {status: 'public'}}

    assert_response :not_found
  end

  test 'bulk_update_samples requires admin auth' do
    sign_in_as users(:carol)
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'public'}}

    assert_response :forbidden
  end

  # --- scoping -----------------------------------------------------------
  # The Samples screen offers two target sets and they must not be
  # confusable: the checkboxes on this page, or every row matching the
  # filter (which can be far more rows than the browser ever rendered).

  test 'scope=selected only touches the checkboxed samples' do
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_match(/Bulk-updated 1 sample/, flash[:notice])
    assert_equal 'curating', @sample_a.reload.status
    assert_equal 'public',   @sample_b.reload.status
  end

  # A sample bulk edit reaches no record field, so it leaves no patch —
  # the event is the only place the actor and the count survive.
  test 'a bulk edit records an event carrying the actor and the row count' do
    assert_difference 'CurationEvent.count', 1 do
      post bulk_update_samples_admin_submission_path(@submission),
            params: {bulk_sample: {status: 'curating'}}
    end

    event = CurationEvent.last

    assert_equal 'admin:bob', event.actor
    assert_equal 2,           event.row_count
    assert_equal 'set 2 samples to curating', event.summary
  end

  test 'the recorded count follows the chosen scope, not the whole submission' do
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_equal 1, CurationEvent.last.row_count
  end

  # An unrecognised scope used to fall through to "the whole submission",
  # so a stale form or a garbled POST widened a handful of checked rows
  # into all of them — and for issuance that cannot be taken back.
  test 'an unrecognised scope is refused, not treated as everything' do
    post bulk_update_samples_admin_submission_path(@submission),
         params: {bulk_sample: {scope: 'all', status: 'curating'}}

    assert_match(/Unknown target/, flash[:alert])
    assert_equal 'private', @sample_a.reload.status
    assert_equal 'public',  @sample_b.reload.status
  end

  test 'an unrecognised scope is refused for accession issuance too' do
    @sample_a.update!(accession: nil, status: 'curating')
    @sample_b.update!(accession: nil, status: 'curating')

    assert_no_difference 'Sample.where.not(accession: nil).count' do
      post admin_submission_accessions_path(@submission),
           params: {bulk_sample: {scope: 'all'}}
    end

    assert_match(/Unknown target/, flash[:alert])
  end

  # Absent entirely is still "the whole submission" — that is the workbench
  # summary bar's button, which posts no scope at all.
  test 'no scope at all still means the whole submission' do
    post bulk_update_samples_admin_submission_path(@submission),
         params: {bulk_sample: {status: 'curating'}}

    assert_match(/Bulk-updated 2 sample/, flash[:notice])
  end

  test 'scope=selected with nothing ticked is refused rather than reported as a no-op success' do
    post bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', status: 'curating'}}

    assert_match(/No samples selected/, flash[:alert])
    assert_equal 'private', @sample_a.reload.status
  end

  # The filtered set is re-derived server-side from the filter params, not
  # from a posted id list — otherwise "all 100K matching" could not work.
  test 'scope=filtered re-derives the target set from the filter params' do
    post bulk_update_samples_admin_submission_path(@submission, q: 'sample-2'),
          params: {bulk_sample: {scope: 'filtered', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_match(/Bulk-updated 1 sample/, flash[:notice])
    assert_equal 'private',  @sample_a.reload.status, 'a posted id outside the filter must not be touched'
    assert_equal 'curating', @sample_b.reload.status
  end

  test 'the redirect keeps the filter so the curator lands back on the same view' do
    post bulk_update_samples_admin_submission_path(@submission, q: 'sample-2'),
          params: {bulk_sample: {scope: 'filtered', status: 'curating'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request, q: 'sample-2')
  end

  test 'the samples tab renders the bulk bar' do
    get samples_admin_submission_request_path(@submission.request)

    assert_response :ok
    assert_match bulk_update_samples_admin_submission_path(@submission), response.body
    assert_match 'name="bulk_sample[status]"',                          response.body
    assert_match 'name="bulk_sample[scope]"',                           response.body
    assert_match 'name="bulk_sample[sample_ids][]"',                    response.body
  end
end
