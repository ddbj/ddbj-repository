require 'test_helper'

class SavedViewTest < ActiveSupport::TestCase
  setup do
    @user = users(:bob)
  end

  # What a view may hold is RequestFilter's business (see its test); this
  # is what a view is on top of it.
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

  # The ledger drops a value it no longer knows rather than refusing it,
  # which is right for a typed URL and wrong for a saved one: dropped
  # silently, "assigned to Tanaka" quietly becomes "everything".
  test 'staleness names what the view no longer matches' do
    view = @user.saved_views.new(
      name:    'Gone',
      filters: {'status' => %w[curating no_such_status], 'assignee' => %w[999]}
    )

    stale = view.staleness(assignee_ids: %w[0 1])

    assert_equal %w[no_such_status], stale.unknown['status']
    assert_equal %w[999],            stale.unknown['assignee']
  end

  test 'a view whose every value still exists says nothing' do
    view = @user.saved_views.new(name: 'Fine', filters: {'db' => %w[biosample], 'assignee' => %w[0]})

    assert_not view.staleness(assignee_ids: %w[0 1]).any?
  end

  # Only a facet that lost ALL of its values stops filtering. One that
  # lost some still constrains on the rest, and claiming otherwise would
  # be the chip inventing a drift — the same sin as the silence it was
  # added to break.
  test 'widened is true only where a facet has nothing left to filter on' do
    partly = @user.saved_views.new(name: 'Partly', filters: {'status' => %w[curating gone]})
    wholly = @user.saved_views.new(name: 'Wholly', filters: {'status' => %w[gone]})

    assert_not partly.staleness(assignee_ids: []).widened
    assert     wholly.staleness(assignee_ids: []).widened
  end

  # The direction nothing else can see. Every value the view names still
  # exists — the universe shrank to meet it, so there is no longer
  # anything for it to exclude. "Unassigned or bob" while bob and dave
  # were staff stops narrowing anything the day dave is not.
  test 'a view whose set now covers everything is stale too' do
    view = @user.saved_views.new(name: 'Mine', filters: {'assignee' => %w[0 1]})

    assert_not view.staleness(assignee_ids: %w[0 1 2]).any?

    shrunk = view.staleness(assignee_ids: %w[0 1])

    assert         shrunk.any?, 'it no longer narrows anything, and nothing became unknown to say so'
    assert         shrunk.widened
    assert_equal   %w[assignee], shrunk.ineffective
    assert_empty   shrunk.unknown
  end

  # An id says nothing to whoever reads the chip, and a curator who has
  # left the staff list is still a User.
  test 'a departed assignee is named' do
    view = @user.saved_views.new(name: 'Dave', filters: {'assignee' => [users(:dave).id.to_s]})

    labels = SavedView.assignee_labels([view])

    assert_equal 'dave', labels[users(:dave).id.to_s]
  end
end
