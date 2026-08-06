require 'test_helper'

class SavedViewTest < ActiveSupport::TestCase
  setup do
    @user = users(:bob)
  end

  # A view is the params and nothing else, so what gets stored has to be
  # exactly what the ledger's own form would have produced.
  test 'normalise keeps the ledger filters and drops everything else' do
    filters = SavedView.normalise({
      'q'              => '  PRJDB  ',
      'db'             => %w[biosample bioproject],
      'status'         => ['curating'],
      'page'           => '3',
      'authenticity_token' => 'nope'
    })

    # Sorted, because a view is a set — see the ordering test below.
    assert_equal({'q' => 'PRJDB', 'db' => %w[bioproject biosample], 'status' => %w[curating]}, filters)
  end

  # `page` above all: a view is a set of rows, not a position in it.
  # Saved with the page, every chip would land wherever its author
  # happened to be scrolled to when they pressed Save.
  test 'normalise drops the page' do
    assert_not_includes SavedView.normalise({'db' => ['biosample'], 'page' => '4'}), 'page'
  end

  # A query string can nest. Coerced with to_s, a Parameters would be
  # stored as a filter value that matches nothing and reads as gibberish.
  test 'normalise ignores values the form could not have produced' do
    filters = SavedView.normalise({'db' => {'evil' => 'x'}, 'q' => {'evil' => 'x'}, 'status' => ['curating']})

    assert_equal({'status' => %w[curating]}, filters)
  end

  test 'normalise caps the query where the search box caps it' do
    long = 'a' * 200

    assert_equal Admin::RequestSearch::MAX_QUERY_LENGTH, SavedView.normalise({'q' => long})['q'].length
  end

  test 'a view of everything is refused — that is the ledger' do
    view = @user.saved_views.new(name: 'Everything', filters: {})

    assert_not view.valid?
    assert_match(/no view to save/, view.errors.full_messages.to_sentence)
  end

  test 'two chips cannot carry the same name' do
    @user.saved_views.create!(name: 'BS to curate', filters: {'db' => %w[biosample]})
    dup = @user.saved_views.new(name: 'bs to curate', filters: {'db' => %w[bioproject]})

    assert_not dup.valid?, 'the name is what the row is navigated by, so case is not a difference'
  end

  test 'another curator may use the same name' do
    @user.saved_views.create!(name: 'BS to curate', filters: {'db' => %w[biosample]})

    assert users(:dave).saved_views.new(name: 'BS to curate', filters: {'db' => %w[biosample]}).valid?
  end

  test 'the row stays a row' do
    SavedView::MAX_PER_USER.times {|i| @user.saved_views.create!(name: "View #{i}", filters: {'db' => %w[biosample]}) }

    over = @user.saved_views.new(name: 'One more', filters: {'db' => %w[bioproject]})

    assert_not over.valid?
    assert_match(/Delete one/, over.errors.full_messages.to_sentence)
  end

  # The page is not part of the view, so being on page 2 of it is still
  # being on it.
  test 'showing? ignores the page and the ordering of a multi-select' do
    view = @user.saved_views.new(name: 'BS', filters: {'db' => %w[bioproject biosample]})

    assert view.showing?({'db' => %w[bioproject biosample], 'page' => '2'})

    # The same two boxes ticked, the other way round. Compared as stored
    # arrays this was a different view, and the chip stayed grey on the
    # ledger it was showing.
    assert view.showing?({'db' => %w[biosample bioproject]})

    assert_not view.showing?({'db' => %w[biosample]})
  end

  # The facet groups live inside the search form with every box checked
  # when the param is absent, so a bare Search posts every value of every
  # facet. The ledger reads that as no constraint; stored, it would be a
  # view of the whole ledger under the name of a filter — and
  # `filters_present` would not catch it, because the hash is not blank.
  test 'a facet with every box ticked is not a filter' do
    filters = SavedView.normalise({
      'db'             => SubmissionRequest.dbs.keys,
      'request_status' => SubmissionRequest.statuses.keys,
      'status'         => Lifecycleable::STATUSES.keys,
      'assignee'       => %w[0 1 2]
    }, assignee_ids: %w[0 1 2])

    assert_empty filters, 'pressing Search selects everything, which is not a view'
  end

  test 'a facet with some boxes ticked still is' do
    filters = SavedView.normalise({'db' => %w[biosample]}, assignee_ids: %w[0])

    assert_equal({'db' => %w[biosample]}, filters)
  end

  # The pinned list is the failure the stale marker cannot see: nothing
  # became unknown, something became newly known. Not storing a
  # full-universe selection is what keeps it from arising.
  test 'a view cannot pin the staff list as it stood when it was saved' do
    everyone = SavedView.assignee_universe
    filters  = SavedView.normalise({'assignee' => everyone, 'db' => %w[biosample]})

    assert_equal({'db' => %w[biosample]}, filters,
                 'a curator joining must not make an old view start hiding their requests')
  end

  # The ledger drops a value it no longer knows rather than refusing it,
  # which is right for a typed URL and wrong for a saved one: dropped
  # silently, "assigned to Tanaka" quietly becomes "everything".
  test 'unknown_values names what the view no longer matches' do
    view = @user.saved_views.new(
      name:    'Gone',
      filters: {'status' => %w[curating no_such_status], 'assignee' => %w[999]}
    )

    unknown = view.unknown_values(assignee_ids: %w[0 1])

    assert_equal %w[no_such_status], unknown['status']
    assert_equal %w[999],            unknown['assignee']
  end

  test 'a view whose every value still exists says nothing' do
    view = @user.saved_views.new(name: 'Fine', filters: {'db' => %w[biosample], 'assignee' => %w[0]})

    assert_empty view.unknown_values(assignee_ids: %w[0 1])
  end

  # Only a facet that lost ALL of its values stops filtering. One that
  # lost some still constrains on the rest, and claiming otherwise would
  # be the chip inventing a drift — the same sin as the silence it was
  # added to break.
  test 'widened_by? is true only where a facet has nothing left to filter on' do
    partly = @user.saved_views.new(name: 'Partly', filters: {'status' => %w[curating gone]})
    wholly = @user.saved_views.new(name: 'Wholly', filters: {'status' => %w[gone]})

    assert_not partly.widened_by?(partly.unknown_values(assignee_ids: []))
    assert     wholly.widened_by?(wholly.unknown_values(assignee_ids: []))
  end

  # An id says nothing to whoever reads the chip, and a curator who has
  # left the staff list is still a User.
  test 'a departed assignee is named' do
    view = @user.saved_views.new(name: 'Dave', filters: {'assignee' => [users(:dave).id.to_s]})

    labels = SavedView.assignee_labels([view], %w[0])

    assert_equal 'dave', labels[users(:dave).id.to_s]
  end
end
