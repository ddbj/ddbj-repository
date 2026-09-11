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
  # deliberately not shared. What a reviewer gets instead is the row's own
  # subtree, drawn on the page — read, never downloaded.
  # Written out rather than grepped for what must not be there. This is
  # the sharpest boundary in the system, and a list nobody has to amend
  # makes every route added under it a decision somebody took on purpose.
  test 'a review link reaches these routes and no others' do
    paths = Rails.application.routes.routes.map { it.path.spec.to_s }.grep(%r{/reviews/})

    assert_equal [
      '/api/reviews/:token(.:format)',
      '/api/reviews/:token/accessions(.:format)',
      '/api/reviews/:token/accessions/:accession(.:format)'
    ], paths
  end

  test "what one accession's record says is readable through the link" do
    submission = submissions(:biosample)
    sample     = samples(:first)

    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice) unless
      @set.inclusions.exists?(submission_request: submission_requests(:biosample))

    @access.shared_accessions.create!(accession: sample.accession, added_by: @alice)

    submission.append_update!({'samples' => [{'alias' => sample.sample_name, 'title' => 'Control timepoint A'}]},
                              actor: 'test')

    get review_accession_path(@access.token, sample.accession)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal sample.accession, body['accession']
    assert_nil   body.dig('record', 'unavailable_reason')

    title = body.dig('record', 'sections').find { it['key'] == 'title' }

    assert_equal 'Control timepoint A', title.dig('node', 'value')
  end

  # Beside the row in the record, not part of it. The submitter's own
  # screen is pinned for this too; a review link is where it matters,
  # because the reader is not entitled to who submitted what.
  test 'a record a link carries never shows who submitted it' do
    submission = submissions(:biosample)
    sample     = samples(:first)

    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice) unless
      @set.inclusions.exists?(submission_request: submission_requests(:biosample))

    @access.shared_accessions.create!(accession: sample.accession, added_by: @alice)

    submission.append_update!(
      {
        'submission' => {'submitters' => [{'name' => 'A Person', 'email' => 'person@example.com'}]},
        'samples'    => [{'alias' => sample.sample_name, 'title' => 'Only this'}]
      },
      actor: 'test'
    )

    get review_accession_path(@access.token, sample.accession)

    assert_conform_schema 200
    assert_equal %w[alias title], response.parsed_body.dig('record', 'sections').pluck('key').sort
    assert_not_includes response.body, 'person@example.com'
  end

  # The same silence the token keeps. Being in the set is not being on the
  # link, and an accession the link does not name is not readable through
  # it however plainly it exists.
  test 'an accession the link does not name is not readable through it' do
    get review_accession_path(@access.token, samples(:first).accession)

    assert_response :not_found
  end

  test 'an accession whose submission has left the set stops being readable' do
    @set.inclusions.find_by!(submission_request: submission_requests(:bioproject)).destroy!

    get review_accession_path(@access.token, 'PRJDB000001')

    assert_response :not_found
  end

  test 'the record a link carries never says how DDBJ is handling it' do
    get review_accession_path(@access.token, 'PRJDB000001')

    assert_conform_schema 200
    assert_equal %w[accession db name details record], response.parsed_body.keys
  end

  # A record is a blob download and a streamed parse. A reviewer refreshing
  # the page should pay for neither.
  test 'a reviewer who already has this version is told so' do
    get review_accession_path(@access.token, 'PRJDB000001')

    assert_response :ok

    get review_accession_path(@access.token, 'PRJDB000001'), headers: {'If-None-Match' => response.headers['ETag']}

    assert_response :not_modified
  end

  # A long sequence, which is the case worth pinning: folding is decided by
  # how tall a section draws, not by which key it is, so the short ones
  # arrive open and that is right. 2,400 bases is above the line; the
  # median ST.26 entry (1,346) is below it and opens.
  test 'a long sequence arrives folded, and says how much is inside it' do
    submission = submissions(:st26)
    entry      = submission.entries.first

    # The fixture's sequences are 21 bases, which fold nowhere. A real one
    # is 1,346 bytes at the median and 240 KB at the top, so the record is
    # given a realistic one rather than the assertion a lenient bound.
    record = JSON.parse(file_fixture('ddbj_record/example.json').read)

    record['sequences']['entries'].each { it['sequence'] = 'ATGC' * 600 }

    submission.ddbj_record.attach(
      io:           StringIO.new(JSON.generate(record)),
      filename:     'example.json',
      content_type: 'application/json'
    )

    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)
    @access.shared_accessions.create!(accession: entry.accession, added_by: @alice)

    get review_accession_path(@access.token, entry.accession)

    assert_conform_schema 200

    sequence = response.parsed_body.dig('record', 'sections').find { it['key'] == 'sequence' }

    assert sequence['folded'], 'a sequence this long is taller than the fold'
    assert_not_nil sequence['precis']
  end

  # The only unauthenticated read in the system, and the most expensive:
  # one record is a whole blob downloaded, checksummed and streamed past.
  # A share link is meant to be forwarded, so the grant is what the
  # ceiling hangs on — there is no account behind it to bound.
  test 'one link cannot be used to walk the archive' do
    with_rate_limiting do
      limit = 120

      limit.times do
        get review_accession_path(@access.token, 'PRJDB000001')

        assert_response :ok
      end

      get review_accession_path(@access.token, 'PRJDB000001')

      assert_response :too_many_requests

      # By the grant, not by the reader: a second link is a second grant.
      other = ReviewerAccess.enable!(SubmissionSet.create!(name: 'Another', owner: @alice),
                                     created_by: @alice, expires_at: 1.week.from_now)

      get review_accession_path(other.token, 'PRJDB000001')

      assert_response :not_found
    end
  end

  test 'an expired link stops answering for the records it carried' do
    @access.update_column(:expires_at, 1.hour.ago)

    get review_accession_path(@access.token, 'PRJDB000001')

    assert_response :not_found
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
