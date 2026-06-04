require 'test_helper'

class AdminCommentsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)

    # Seed an initial chain entry so the submission has a materialised
    # record to mutate. Without this, materialise_at returns {} and the
    # patch chain starts from scratch — which is also a valid path, but
    # exercises a different code path than "edit an existing record".
    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {'submitters' => [{'first_name' => 'Hanako'}]}
      },
      actor:  'test-seed',
      source: :manual
    )
  end

  test 'PATCH update adds submission.comments (one per line) and appends a SubmissionUpdate' do
    initial_chain_length = @submission.updates.count

    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: "first comment\nsecond comment\n"}}

    assert_redirected_to admin_submission_path(@submission)

    @submission.reload
    assert_equal initial_chain_length + 1, @submission.updates.count, 'expected one new SubmissionUpdate'
    assert_equal ['first comment', 'second comment'],
                 @submission.materialised_record.dig('submission', 'comments')

    latest_patch = JSON.parse(@submission.updates.order(:id).last.patch)
    assert(latest_patch.any? {|op| op['path'].include?('/submission/comments') },
           "expected at least one op on /submission/comments; got: #{latest_patch.inspect}")
  end

  test 'PATCH update with same comments value generates no patch (no-op)' do
    # Seed a comments value, then try to "save" the same value.
    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {'submitters' => [{'first_name' => 'Hanako'}], 'comments' => ['existing']}
      },
      actor:  'test-seed-2',
      source: :manual
    )
    chain_before = @submission.updates.count

    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: 'existing'}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/unchanged/, flash[:notice])
    assert_equal chain_before, @submission.updates.count, 'no-op save must not create a new SubmissionUpdate'
  end

  test 'PATCH update with empty body removes the comments key entirely' do
    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {'submitters' => [{'first_name' => 'Hanako'}], 'comments' => ['will be removed']}
      },
      actor:  'test-seed-3',
      source: :manual
    )

    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: ''}}

    assert_redirected_to admin_submission_path(@submission)
    @submission.reload
    refute @submission.materialised_record.dig('submission')&.key?('comments'),
           'empty body must drop the comments key (not store an empty array)'
  end

  test 'PATCH update drops blank lines from the textarea' do
    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: "a\n\n  \nb\n"}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal %w[a b],
                 @submission.reload.materialised_record.dig('submission', 'comments')
  end

  test 'PATCH update extends an existing 1-element comments list to 2 (no bag-descent false-positive)' do
    # Pre-fix bug: the bag-descent guard walked every path prefix and
    # called PathClassifier.array_mode which returns the default 'bag'
    # for unregistered pointers. /submission (a Hash, not an array) is
    # unregistered, so the guard treated it as a bag and rejected the
    # `add /submission/comments/1 ...` op produced by extending an
    # existing one-element comments list. Fixed by switching the guard
    # to PathClassifier.explicit_bag? — only paths registered as bag
    # in array-modes.yml count.
    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {'submitters' => [{'first_name' => 'Hanako'}], 'comments' => ['first']}
      },
      actor:  'test-seed-extend',
      source: :manual
    )

    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: "first\nsecond"}}

    assert_redirected_to admin_submission_path(@submission)
    refute_match(/Cannot edit/, flash[:alert].to_s)
    assert_equal %w[first second], @submission.reload.materialised_record.dig('submission', 'comments')
  end

  test 'PATCH update preserves unrelated submission keys' do
    # Submitters is the other field in the seeded submission block. It
    # MUST round-trip unchanged when we edit comments.
    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: 'note'}}

    assert_redirected_to admin_submission_path(@submission)
    sb = @submission.reload.materialised_record.fetch('submission')
    assert_equal [{'first_name' => 'Hanako'}], sb['submitters']
    assert_equal ['note'],                     sb['comments']
  end

  test 'show page renders the comments form when materialised record is present' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Comments',                                    response.body
    assert_match admin_submission_comments_path(@submission),   response.body
    assert_match 'name="submission_comments[body]"',            response.body
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_submission_comments_path(@submission),
          params: {submission_comments: {body: 'x'}}

    assert_response :forbidden
  end
end
