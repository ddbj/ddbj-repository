require 'test_helper'

class SetAccessionsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
  end

  test 'lists what the caller could put on the link' do
    get set_accessions_path(@set)

    assert_conform_schema 200

    row = response.parsed_body.sole

    assert_equal 'PRJDB000001',             row['accession']
    assert_equal 'bioproject',              row['db']
    assert_equal 'Primary fixture project', row['name']
    assert_equal false,                     row['shared']
  end

  # The list is drawn with its ticks in place rather than as a list beside
  # a second list of what is already on the link.
  test 'says which of them are already on the link' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    get set_accessions_path(@set)

    assert_conform_schema 200
    assert_equal true, response.parsed_body.sole['shared']
  end

  # Only the owner shares their own work, so a candidate list holding a
  # colleague's would be offering what the next request refuses.
  test "a colleague's submission is not a candidate, even though it can be read" do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    get set_accessions_path(@set)

    assert_conform_schema 200
    assert_empty response.parsed_body
  end

  # It spans three tables, and a page of the whole is a page of none of
  # them — which is the reason for the union behind it.
  test 'spans the databases the set holds' do
    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:st26),      added_by: @alice)

    get set_accessions_path(@set)

    assert_conform_schema 200

    assert_equal %w[biosample bioproject st26].sort, response.parsed_body.pluck('db').uniq.sort
    assert_equal response.parsed_body.pluck('accession').sort, response.parsed_body.pluck('accession')
  end

  test 'is paginated' do
    get set_accessions_path(@set)

    assert_response :ok
    assert_equal '1', response.headers['Total-Pages']
  end

  test 'a set you are not in is not a set whose accessions you can list' do
    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app { get set_accessions_path(@set) }

    assert_conform_schema 404
  end
end
