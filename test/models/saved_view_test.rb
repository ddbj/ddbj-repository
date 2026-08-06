require 'test_helper'

class SavedViewTest < ActiveSupport::TestCase
  setup do
    @user = users(:bob)
  end

  # A view is the params and nothing else, so what gets stored has to be
  # exactly what the ledger's own form would have produced.
  test 'normalise keeps the ledger filters and drops everything else' do
    filters = SavedView.normalise(
      'q'              => '  PRJDB  ',
      'db'             => %w[biosample bioproject],
      'status'         => ['curating'],
      'page'           => '3',
      'authenticity_token' => 'nope'
    )

    assert_equal({'q' => 'PRJDB', 'db' => %w[biosample bioproject], 'status' => %w[curating]}, filters)
  end

  # `page` above all: a view is a set of rows, not a position in it.
  # Saved with the page, every chip would land wherever its author
  # happened to be scrolled to when they pressed Save.
  test 'normalise drops the page' do
    assert_not_includes SavedView.normalise('db' => ['biosample'], 'page' => '4'), 'page'
  end

  # A query string can nest. Coerced with to_s, a Parameters would be
  # stored as a filter value that matches nothing and reads as gibberish.
  test 'normalise ignores values the form could not have produced' do
    filters = SavedView.normalise('db' => {'evil' => 'x'}, 'q' => {'evil' => 'x'}, 'status' => ['curating'])

    assert_equal({'status' => %w[curating]}, filters)
  end

  test 'normalise caps the query where the search box caps it' do
    long = 'a' * 200

    assert_equal Admin::RequestSearch::MAX_QUERY_LENGTH, SavedView.normalise('q' => long)['q'].length
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
    view = @user.saved_views.new(name: 'BS', filters: {'db' => %w[biosample]})

    assert view.showing?('db' => ['biosample'], 'page' => '2')
    assert_not view.showing?('db' => %w[biosample bioproject])
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
end
