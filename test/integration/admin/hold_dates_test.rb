require 'test_helper'

class AdminHoldDatesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)

    # Seed a chain entry so the submission has a materialised record to
    # mutate.
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}]}},
      actor:  'test-seed',
      source: :manual
    )
  end

  test 'PATCH update sets hold_date and appends a SubmissionUpdate' do
    chain_before = @submission.updates.count

    patch admin_submission_hold_date_path(@submission),
          params: {submission: {hold_date: '2026-12-31'}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/Hold date saved/, flash[:notice])
    @submission.reload
    assert_equal chain_before + 1,  @submission.updates.count
    assert_equal '2026-12-31',      @submission.materialised_record.dig('submission', 'hold_date')
  end

  test 'PATCH update with blank value drops the hold_date key' do
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}], 'hold_date' => '2026-12-31'}},
      actor:  'test-seed-2',
      source: :manual
    )

    patch admin_submission_hold_date_path(@submission),
          params: {submission: {hold_date: ''}}

    assert_redirected_to admin_submission_path(@submission)
    refute @submission.reload.materialised_record.dig('submission')&.key?('hold_date'),
           'blank input must drop the hold_date key (not store an empty string)'
  end

  test 'PATCH update with the same value generates no patch (no-op)' do
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}], 'hold_date' => '2026-12-31'}},
      actor:  'test-seed-3',
      source: :manual
    )
    chain_before = @submission.updates.count

    patch admin_submission_hold_date_path(@submission),
          params: {submission: {hold_date: '2026-12-31'}}

    assert_match(/unchanged/, flash[:notice])
    assert_equal chain_before, @submission.reload.updates.count
  end

  test 'PATCH update rejects month-name / non-ISO inputs strictly' do
    ['May', '12', '2026/12/31', '2026-13-01', '2026-02-30', 'today'].each do |bad|
      patch admin_submission_hold_date_path(@submission),
            params: {submission: {hold_date: bad}}

      assert_redirected_to admin_submission_path(@submission)
      assert_match(/valid YYYY-MM-DD/, flash[:alert], "expected reject for #{bad.inspect}")
      assert_nil @submission.reload.materialised_record.dig('submission', 'hold_date'),
                 "must not fabricate hold_date from #{bad.inspect}"
    end
  end

  test 'show page renders the hold_date form' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Hold date',                                   response.body
    assert_match admin_submission_hold_date_path(@submission),  response.body
    assert_match 'name="submission[hold_date]"',                response.body
  end

  test 'show page pre-populates the date input with the current value' do
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}], 'hold_date' => '2026-12-31'}},
      actor:  'test-seed-4',
      source: :manual
    )

    get admin_submission_path(@submission)

    assert_response :ok
    assert_match(/value="2026-12-31"/, response.body)
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_submission_hold_date_path(@submission),
          params: {submission: {hold_date: '2026-12-31'}}

    assert_response :forbidden
  end
end
