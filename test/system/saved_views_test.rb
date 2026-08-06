require 'application_system_test_case'

# Naming a filter, coming back to it, and taking the name away.
#
# The feature exists because the ledger's state is entirely in the URL —
# so what is saved is a link, and the test is that pressing the name puts
# the same rows back on screen.
class SavedViewsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  test 'a filter can be named, and the name brings it back' do
    visit admin_submission_requests_path(db: %w[biosample])

    # Already filled in, so saving is a press rather than a naming
    # decision — and short, because the chip is what the curator will
    # recognise the view by and the full summary is on screen anyway.
    assert_field 'Name for this view', with: 'Biosample'

    fill_in 'Name for this view', with: 'BS to curate'
    click_button 'Save'

    assert_text 'Saved “BS to curate”'

    # Away, and back by name.
    visit admin_submission_requests_path

    assert_no_selector '[data-test-saved-view="BS to curate"][aria-current]'

    click_link 'BS to curate'

    assert_selector '[data-test-saved-view="BS to curate"][aria-current="true"]'
    assert_text 'matching the current filter'
  end

  # A chip is a link to the ledger, not to a page only its owner can
  # reach — the URL it lands on is the one they can paste to a colleague.
  test 'the chip lands on an ordinary shareable ledger URL' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path
    click_link 'BS'

    assert_current_path admin_submission_requests_path(db: %w[biosample])
  end

  # Nothing to name on an unfiltered ledger: that view is the link in the
  # nav, and offering to save it would fill the row with duplicates of
  # the screen everybody is already on.
  test 'saving is offered only where something is filtered' do
    visit admin_submission_requests_path

    assert_no_button 'Save this view'

    visit admin_submission_requests_path(q: 'PRJDB')

    assert_button 'Save this view'
  end

  test 'a name already taken is refused rather than silently replacing' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[bioproject])

    fill_in 'Name for this view', with: 'BS'
    click_button 'Save'

    assert_text 'Name has already been taken'
    assert_equal 1, users(:bob).saved_views.count

    # And the correction is where the mistake was. Redirecting to a fresh
    # page left the message with no form under it: the collapse was shut
    # and the field back to its suggestion, so a rejected name had to be
    # found, reopened and retyped.
    assert_field 'Name for this view', with: 'BS'
  end

  # Pressing Search ticks every box in every facet, which the ledger
  # reads as no constraint. Offering to save that would put the whole
  # ledger in the row under a name — and the refusal a curator would get
  # for it ("nothing is filtered") reads as a bug on a screen that just
  # invited them to save.
  test 'a bare search is not something to save' do
    visit admin_submission_requests_path
    click_button 'Search'

    assert_no_button 'Save this view'
  end

  # A view is a set of rows; the page is where the curator was standing.
  # Both matter on the way back — one to the chip, the other to them.
  test 'deleting leaves the curator on the page they were reading' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[bioproject], page: '1')
    click_button 'Delete saved view BS'

    assert_current_path(/page=1/)
  end

  test 'deleting takes the chip away and leaves the rows where they were' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[biosample])

    click_button 'Delete saved view BS'

    assert_text 'Deleted “BS”'
    assert_no_selector '[data-test-saved-view="BS"]'

    # Still filtered: deleting a name is not a navigation.
    assert_selector '[data-test-active-filter]', text: 'Database: Biosample'
  end

  # The ledger drops a value it no longer knows, so a stale view still
  # opens — showing more than it was saved with. Silence there is the
  # failure: "assigned to Tanaka" becomes "everything" and reads as a
  # quiet morning.
  test 'a view that no longer matches what it named is marked' do
    users(:bob).saved_views.create!(name: 'Gone', filters: {'assignee' => %w[999999]})

    visit admin_submission_requests_path

    assert_selector '[data-test-saved-view-stale="Gone"]'
  end

  test 'a view whose values all still exist is not marked' do
    users(:bob).saved_views.create!(name: 'Mine', filters: {'assignee' => [users(:bob).id.to_s]})

    visit admin_submission_requests_path

    assert_selector    '[data-test-saved-view="Mine"]'
    assert_no_selector '[data-test-saved-view-stale="Mine"]'
  end

  # The badge row used to read the params, which say "three databases are
  # selected" when the truth is "no database filter is on" — over a count
  # that says 989 requests, unqualified, two lines above.
  test 'ticking every box in a facet is described as no filter at all' do
    visit admin_submission_requests_path(db: SubmissionRequest.dbs.keys)

    assert_no_selector '[data-test-active-filter]'
    assert_no_link     'Clear'
  end

  # `0` is the "unassigned" box and the rest are user ids, neither of
  # which means anything read back as a number.
  test 'an assignee filter is described by name, not by id' do
    visit admin_submission_requests_path(assignee: ['0'])

    assert_selector '[data-test-active-filter]', text: 'Assignee: Unassigned'

    visit admin_submission_requests_path(assignee: [users(:dave).id.to_s])

    assert_selector '[data-test-active-filter]', text: 'Assignee: dave'
  end

  # Personal, so one curator's row is not another's.
  test 'saved views belong to the curator who saved them' do
    users(:dave).saved_views.create!(name: "Dave's", filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path

    assert_no_selector '[data-test-saved-view="Dave\'s"]'
  end
end

# The other half of "everything selected is the same as nothing
# selected": the form stops posting a facet that constrains nothing, so
# the two arrive at the same address rather than at two URLs the screen
# has to describe identically.
class LedgerFilterFormJavaScriptTest < JavaScriptSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  test 'a fully-ticked facet is left out of the URL' do
    visit admin_submission_requests_path

    click_button 'Search'

    # Not one of the four facets, where the form used to post every value
    # of all of them.
    assert_no_current_path(/db%5B%5D|request_status%5B%5D|status%5B%5D|assignee%5B%5D/)
  end

  test 'a facet the curator narrowed still travels' do
    visit admin_submission_requests_path

    click_button 'More filters'
    uncheck 'ST.26'
    click_button 'Search'

    assert_current_path(/db%5B%5D=bioproject/)
    assert_no_current_path(/db%5B%5D=st26/)
  end
end
