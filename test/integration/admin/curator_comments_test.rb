require 'test_helper'

class AdminCuratorCommentsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
    @submission = submissions(:bioproject)
  end

  test 'PATCH update writes the body to Submission#curator_comment' do
    patch admin_submission_curator_comment_path(@submission),
          params: {submission_curator_comment: {body: "first note\nsecond note"}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal "first note\nsecond note", @submission.reload.curator_comment
  end

  test 'PATCH update with empty body nulls the column' do
    @submission.update_columns(curator_comment: 'existing')

    patch admin_submission_curator_comment_path(@submission),
          params: {submission_curator_comment: {body: ''}}

    assert_redirected_to admin_submission_path(@submission)
    assert_nil @submission.reload.curator_comment
  end

  test 'PATCH update does NOT touch the patch chain' do
    assert_no_difference '@submission.updates.count' do
      patch admin_submission_curator_comment_path(@submission),
            params: {submission_curator_comment: {body: 'note'}}
    end
  end

  test 'show page renders the curator comment form even with no materialised record' do
    # curator_comment is a typed column, independent of the patch chain —
    # the form MUST stay editable when the v3 record can't be replayed.
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Curator comment',                                  response.body
    assert_match admin_submission_curator_comment_path(@submission), response.body
    assert_match 'name="submission_curator_comment[body]"',          response.body
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_submission_curator_comment_path(@submission),
          params: {submission_curator_comment: {body: 'x'}}

    assert_response :forbidden
  end
end
