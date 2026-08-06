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
    assert_field 'Name for this view', with: 'BioSample'

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

  # Opening the form is a decision that has to be reversible on its own
  # terms. Closing the collapse again is something to work out rather
  # than see — and after a refused save it does not even work, since the
  # name is in the URL and the form comes back on the next reload.
  test 'the save form can be abandoned' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[bioproject])

    fill_in 'Name for this view', with: 'BS'
    click_button 'Save'

    assert_text 'Name has already been taken'

    click_link 'Cancel'

    # Folded away again — `aria-expanded` rather than the class, because
    # that is the state as anything but a stylesheet sees it.
    assert_selector 'button[aria-expanded="false"]', text: 'Save this view'
    assert_no_text  'Name has already been taken'
    assert_field    'Name for this view', with: 'BioProject'

    # The same rows it was opened over. Cancelling a name is not a
    # navigation either.
    assert_selector '[data-test-active-filter]', text: 'Database: BioProject'
  end

  # The one refusal where the field is empty. Asking the form to reopen
  # on `present?` shut it on exactly that message, leaving "Name can't be
  # blank" with nothing under it to correct.
  test 'a blank name comes back to the form, like any other refusal' do
    visit admin_submission_requests_path(db: %w[biosample])

    fill_in 'Name for this view', with: '  '
    click_button 'Save'

    assert_text 'Name can\'t be blank'
    assert_selector 'button[aria-expanded="true"]', text: 'Save this view'
  end

  # A stale view still opens; what it must not do is claim to be showing
  # when the ledger dropped the value it names.
  test 'a view the ledger cannot apply does not report itself as showing' do
    users(:bob).saved_views.create!(name: 'Gone', filters: {'status' => %w[no_such_status]})

    visit admin_submission_requests_path(status: %w[no_such_status])

    assert_no_selector '[data-test-active-filter]'
    assert_no_selector '[data-test-saved-view="Gone"][aria-current]'
    assert_selector    '[data-test-saved-view-stale="Gone"]'
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

    within '[data-test-manage-saved-views]' do
      click_button 'Delete saved view BS'
    end

    assert_current_path(/page=1/)
  end

  test 'deleting takes the chip away and leaves the rows where they were' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[biosample])

    within '[data-test-manage-saved-views]' do
      click_button 'Delete saved view BS'
    end

    assert_text 'Deleted “BS”'
    assert_no_selector '[data-test-saved-view="BS"]'

    # Still filtered: deleting a name is not a navigation.
    assert_selector '[data-test-active-filter]', text: 'Database: BioSample'
  end

  # The obvious thing to press to take an applied view off was the ×
  # beside its name — which deleted the view for good. The free operation
  # and the irreversible one were the same gesture in the same place, so
  # the free one is now what the name itself does.
  test 'pressing the view that is showing takes it off' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path(db: %w[biosample])

    assert_selector '[data-test-saved-view="BS"][aria-current="true"]'

    # Said on the chip rather than in a `title` nobody hovers: which of
    # the two things this press does depends on the state, so the state
    # has to be legible without asking for it.
    assert_selector '[data-test-saved-view="BS"]', text: 'on · press to clear'

    click_link 'BS'

    assert_current_path admin_submission_requests_path
    assert_no_selector '[data-test-saved-view="BS"][aria-current]'

    # Taking the filter off is not throwing the view away.
    assert_selector '[data-test-saved-view="BS"]'
    assert_equal 1, users(:bob).saved_views.count
  end

  # Where a view is managed, as opposed to where it is used. Not a delete
  # mode: that makes everybody carry a memory of it for a rare press.
  test 'deleting is not on the chip' do
    users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path

    # One delete control on the screen, and it is in the menu rather
    # than against the name.
    assert_selector '[aria-label="Delete saved view BS"]', count: 1
    assert_selector '[data-test-manage-saved-views] [aria-label="Delete saved view BS"]'
  end

  # The name is the only thing a view has that the URL does not, so it is
  # the only thing to edit — and the only way to fix a bad one was to
  # delete it and rebuild the filter.
  test 'a view can be renamed without being rebuilt' do
    view = users(:bob).saved_views.create!(name: 'BS', filters: {'db' => %w[biosample]})

    visit admin_submission_requests_path

    within '[data-test-manage-saved-views]' do
      fill_in 'New name for BS', with: 'BS to curate'
      click_button 'Save name'
    end

    assert_text 'Renamed to “BS to curate”'
    assert_equal({'db' => %w[biosample]}, view.reload.filters, 'renaming does not touch what it points at')
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

  # Naming the view after the first value left a filter on two databases
  # suggesting the name of one of them, with the other nowhere on screen.
  test 'the suggested name carries every value it is filtered by' do
    visit admin_submission_requests_path(db: %w[st26 biosample])

    assert_field 'Name for this view', with: 'ST.26, BioSample'
  end

  test 'the suggested name spans facets rather than stopping at the first' do
    visit admin_submission_requests_path(db: %w[biosample], status: %w[curating])

    assert_field 'Name for this view', with: 'BioSample · Curating'
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
