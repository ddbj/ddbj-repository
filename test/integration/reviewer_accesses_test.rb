require 'test_helper'

class ReviewerAccessesTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission_request = submission_requests(:bioproject) # owned by :alice
  end

  test 'GET show reports disabled when no link exists' do
    get submission_request_reviewer_access_path(@submission_request)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['enabled']
  end

  test 'GET show returns the link once enabled' do
    @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)

    get submission_request_reviewer_access_path(@submission_request)

    assert_conform_schema 200
    assert_equal true, response.parsed_body['enabled']
    assert_match %r{/web/reviews/.+}, response.parsed_body['url']
  end

  test 'POST enables reviewer access and returns the share URL + expiry' do
    assert_difference 'ReviewerAccess.count', 1 do
      post submission_request_reviewer_access_path(@submission_request),
           params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 201
    assert_equal true, response.parsed_body['enabled']
    assert_match %r{/web/reviews/.+}, response.parsed_body['url']
    assert_not_nil response.parsed_body['expires_at']
  end

  test 'POST regenerates the link, invalidating the old token' do
    old = @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)

    post submission_request_reviewer_access_path(@submission_request),
         params:  {reviewer_access: {expires_at: 1.month.from_now.iso8601}}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 201
    assert_nil          ReviewerAccess.find_by(token: old.token)
    assert_equal        1, ReviewerAccess.where(submission_request: @submission_request).count
    assert_not_includes response.parsed_body['url'], old.token
  end

  test 'POST with a past expires_at is rejected' do
    assert_no_difference 'ReviewerAccess.count' do
      post submission_request_reviewer_access_path(@submission_request),
           params:  {reviewer_access: {expires_at: 1.day.ago.iso8601}}.to_json,
           headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
  end

  test 'a rejected re-enable leaves the existing link intact' do
    existing = @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)

    post submission_request_reviewer_access_path(@submission_request),
         params:  {reviewer_access: {expires_at: 1.day.ago.iso8601}}.to_json,
         headers: JSON_HEADERS

    assert_response :unprocessable_content
    assert_equal existing, @submission_request.reload.reviewer_access
  end

  test 'DELETE disables reviewer access' do
    @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)

    assert_difference 'ReviewerAccess.count', -1 do
      delete submission_request_reviewer_access_path(@submission_request)
    end

    assert_response :no_content
  end

  test "a non-owner cannot reach another user's reviewer access" do
    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"

    get submission_request_reviewer_access_path(@submission_request) # @submission_request is alice's

    assert_response :not_found
  end
end
