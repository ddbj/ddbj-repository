require 'test_helper'

class SubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission = submissions(:st26)

    attach_submission_files @submission
  end

  test 'index across all dbs' do
    Submission.dbs.each_key {|db| attach_submission_files submissions(db.to_sym) }

    get submissions_path

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes ids, submissions(:st26).id
    assert_includes ids, submissions(:bioproject).id
    assert_includes ids, submissions(:biosample).id
  end

  test 'index filters by ?db=' do
    Submission.dbs.each_key {|db| attach_submission_files submissions(db.to_sym) }

    get submissions_path(db: 'st26')

    assert_conform_schema 200

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_equal ['st26'],            body.pluck('db').uniq
    assert_includes     ids,          submissions(:st26).id
    assert_not_includes ids,          submissions(:bioproject).id
  end

  test 'show' do
    get submission_path(id: @submission.id)

    assert_conform_schema 200
    assert_equal @submission.id, response.parsed_body['id']
  end
end
