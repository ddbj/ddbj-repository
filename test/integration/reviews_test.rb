require 'test_helper'

class ReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:biosample),  added_by: @alice)

    @access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    @access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)
  end

  # No Authorization header is ever set here — the whole point is access
  # without logging in.

  test 'GET with a valid token returns the set the link was made for' do
    get review_path(@access.token)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 'Deep sea study', body['name']
    assert_not_nil body['expires_at']
  end

  test 'what was put on the link is its own list' do
    get review_accessions_path(@access.token)

    assert_conform_schema 200

    shared = response.parsed_body.sole

    assert_equal 'PRJDB000001',             shared['accession']
    assert_equal 'bioproject',              shared['db']
    assert_equal 'Primary fixture project', shared['name']
  end

  # There is no ceiling on what a link may carry, so nothing may assume it
  # arrives whole. `Total-Pages` is how the reviewer's page knows there is
  # more of it.
  test 'the list is paginated' do
    get review_accessions_path(@access.token)

    assert_response :ok
    assert_equal '1', response.headers['Total-Pages']
  end

  # Being in the set is not being on the link. Naming the accessions is
  # the whole of what the feature does, so a set holding two submissions
  # and a link naming one of them has to show one.
  test 'an accession nobody put on the link is not on it' do
    get review_accessions_path(@access.token)

    assert_response :ok
    assert_not_includes response.parsed_body.pluck('accession'), samples(:first).accession
  end

  test 'what each record says travels as labelled facts' do
    @access.shared_accessions.create!(accession: samples(:first).accession, added_by: @alice)

    get review_accessions_path(@access.token)

    assert_conform_schema 200

    sample = response.parsed_body.find { it['db'] == 'biosample' }

    assert_equal 'fixture-sample-1', sample['name']
    assert_equal 'Generic.1.0',      sample.fetch('details').find { it['label'] == 'Package' }['value']
  end

  # The token is unauthenticated, so the reviewer's view is not the
  # members' view with fields left out — it is a different view. Where
  # DDBJ has got to with a record, whose it is, and the collaboration
  # around it are none of them a reviewer's business.
  test 'the reviewer view never carries the curation status, the owner, or the roster' do
    get review_path(@access.token)

    assert_response :ok
    assert_equal %w[name expires_at], response.parsed_body.keys

    get review_accessions_path(@access.token)

    assert_response :ok
    assert_equal %w[accession db name details], response.parsed_body.sole.keys
    assert_not_includes response.body, @alice.uid
  end

  # At accession granularity there is nothing to hand over: a record or a
  # flatfile is the whole submission, which is the thing that was
  # deliberately not shared.
  test 'there are no files on a review link' do
    paths = Rails.application.routes.routes.map { it.path.spec.to_s }.grep(%r{/reviews/})

    assert_equal ['/api/reviews/:token(.:format)', '/api/reviews/:token/accessions(.:format)'], paths
  end

  test 'an accession whose submission has left the set goes with it' do
    @set.inclusions.find_by!(submission_request: submission_requests(:bioproject)).destroy!

    get review_accessions_path(@access.token)

    assert_conform_schema 200
    assert_empty response.parsed_body
  end

  test 'an expired token 404s' do
    @access.update_column(:expires_at, 1.hour.ago)

    with_exceptions_app { get review_path(@access.token) }

    assert_conform_schema 404

    with_exceptions_app { get review_accessions_path(@access.token) }

    assert_conform_schema 404
  end

  test 'an unknown token 404s' do
    with_exceptions_app { get review_path('does-not-exist') }

    assert_conform_schema 404

    with_exceptions_app { get review_accessions_path('does-not-exist') }

    assert_conform_schema 404
  end
end
