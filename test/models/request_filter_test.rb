require 'test_helper'

# What the ledger is actually filtered by, as opposed to what happened to
# arrive in the query string. Everything that describes the screen reads
# this — the badge row, the Clear link, the empty state's choice of
# words, and what a saved view stores.
class RequestFilterTest < ActiveSupport::TestCase
  test 'it keeps the ledger filters and drops everything else' do
    filters = RequestFilter.normalise({
      'q'                  => '  PRJDB  ',
      'db'                 => %w[biosample bioproject],
      'status'             => ['curating'],
      'page'               => '3',
      'authenticity_token' => 'nope'
    })

    # Canonically ordered, because a facet is a set — see below.
    assert_equal({'q' => 'PRJDB', 'db' => %w[bioproject biosample], 'status' => %w[curating]}, filters)
  end

  # The order is the boxes' own, not alphabetical: this is what a badge
  # reads back and what a saved view is named after, and "ST.26,
  # BioSample" is the order the curator ticked them in.
  test 'values come back in the order the facet lists them' do
    filters = RequestFilter.normalise({'db' => %w[biosample st26]})

    assert_equal %w[st26 biosample], filters['db']
  end

  # `page` above all: a filter is a set of rows, not a position in it.
  # Stored, every chip would land wherever its author happened to be
  # scrolled to when they pressed Save.
  test 'it drops the page' do
    assert_not_includes RequestFilter.normalise({'db' => ['biosample'], 'page' => '4'}), 'page'
  end

  # A query string can nest. Coerced with to_s, a Parameters would become
  # a filter value that matches nothing and reads as gibberish.
  test 'it ignores values the form could not have produced' do
    filters = RequestFilter.normalise({'db' => {'evil' => 'x'}, 'q' => {'evil' => 'x'}, 'status' => ['curating']})

    assert_equal({'status' => %w[curating]}, filters)
  end

  test 'it caps the query where the search box caps it' do
    long = 'a' * 200

    assert_equal Admin::RequestSearch::MAX_QUERY_LENGTH, RequestFilter.normalise({'q' => long})['q'].length
  end

  # The heart of it. The facet groups live inside the search form with
  # every box checked when the param is absent, so a bare Search posts
  # every value of every facet — which the ledger reads as no constraint.
  # A screen describing that as a filter contradicts its own row count.
  test 'a facet with every box ticked is not a filter' do
    filters = RequestFilter.normalise({
      'db'             => SubmissionRequest.dbs.keys,
      'request_status' => SubmissionRequest.statuses.keys,
      'status'         => Lifecycleable::STATUSES.keys,
      'assignee'       => %w[0 1 2]
    }, assignee_ids: %w[0 1 2])

    assert_empty filters, 'pressing Search selects everything, which is not a filter'
  end

  # And the other end of the same rule, which the ledger has always
  # applied: Deselect all means "do not narrow on this".
  test 'a facet with no box ticked is not a filter either' do
    assert_empty RequestFilter.normalise({'db' => []})
  end

  test 'a facet with some boxes ticked is' do
    assert_equal({'db' => %w[biosample]}, RequestFilter.normalise({'db' => %w[biosample]}))
  end

  # Ticking every assignee pins the staff list as it stood. A saved view
  # holding one would start hiding a new curator's requests the day they
  # joined — and nothing would have become unknown, so nothing could
  # notice.
  test 'the staff list cannot be pinned by ticking all of it' do
    filters = RequestFilter.normalise({'assignee' => RequestFilter.assignee_universe, 'db' => %w[biosample]})

    assert_equal({'db' => %w[biosample]}, filters)
  end

  # An id says nothing to whoever reads it back, and `0` is not an id at
  # all — it is the "nobody has claimed this" box.
  test 'assignees are named' do
    labels = RequestFilter.assignee_labels(['0', users(:dave).id.to_s])

    assert_equal 'Unassigned', labels['0']
    assert_equal 'dave',       labels[users(:dave).id.to_s]
  end

  test 'an assignee whose row is gone keeps its id rather than vanishing' do
    assert_not_includes RequestFilter.assignee_labels(%w[999999]), '999999'
  end
end
