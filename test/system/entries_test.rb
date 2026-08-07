require 'application_system_test_case'

# An ST.26 submission's entries, the tab a BioSample submission fills with
# its samples. A curator retracts one here, and that is what keeps it out
# of the flatfile.
class EntriesSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!
    ApplySubmissionRequestJob.perform_now request

    @request = request.reload
    @entries = @request.submission.entries.order(:id).to_a
  end

  # The tab is one slot named for what the submission's rows are. A
  # BioProject has no bag of anything and gets neither name.
  test 'the rows tab is called Entries for an ST.26 submission' do
    visit admin_submission_request_path(@request)

    assert_link 'Entries'
    assert_no_link 'Samples'

    click_link 'Entries'

    assert_selector 'h2', text: 'Entries'
    assert_text @entries.first.accession
    assert_text @entries.first.entry_id
  end

  test 'the entries can be narrowed to the one being fixed' do
    visit entries_admin_submission_request_path(@request)

    assert_text @entries.first.accession
    assert_text @entries.second.accession

    fill_in 'Search', with: @entries.first.accession
    click_button 'Filter'

    assert_text    @entries.first.accession
    assert_no_text @entries.second.accession

    click_link 'Clear'

    assert_text @entries.second.accession
  end

  # Retracting is the point of the screen, so it has to be reachable from
  # it — and it has to say what it did.
  test 'a checked entry can be withdrawn from the bulk bar' do
    visit entries_admin_submission_request_path(@request)

    check "Select #{@entries.first.entry_id}"
    select 'Withdrawn', from: 'bulk_row[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated 1'
    assert_equal 'withdrawn', @entries.first.reload.status
    assert_equal 'accession_issued', @entries.second.reload.status
  end

  test 'the status filter finds what was retracted' do
    @entries.first.update!(status: :canceled)

    visit entries_admin_submission_request_path(@request, status: 'canceled')

    assert_text    @entries.first.accession
    assert_no_text @entries.second.accession
  end

  # A BioSample submission keeps its own tab, under its own name.
  test 'a BioSample submission still gets Samples' do
    visit admin_submission_request_path(submission_requests(:biosample))

    assert_link 'Samples'
    assert_no_link 'Entries'
  end

  # The entries are curation rows now, so everything counted from them
  # follows. The progress bar could not leave "Applied" for an ST.26
  # submission before, however far along its entries were.
  test 'the progress bar reads the entries' do
    @request.submission.entries.update_all(status: Lifecycleable::STATUSES.fetch('public'))

    state = CurationState.new(@request.reload)

    assert_equal 2, state.row_count, 'the entries are the rows now'
    assert state.curated?

    visit admin_submission_request_path(@request)

    within '.workbench-progress' do
      assert_text 'Public'
    end
  end

  # ST.26 entries are created with their accession, so there is never
  # anything to issue — the ledger has to say so rather than offer a
  # button that allocates nothing.
  test 'there is nothing to issue accessions for' do
    plan = AccessionPlan.for([@request.submission])

    assert_equal 0, plan.items.sole.issuable
  end

  # Withdrawing an entry keeps it out of the flatfile, so a curator who
  # did it in error has to be able to undo it. Leaving the state an entry
  # starts in off the settable list made retraction one-way.
  test 'a withdrawn entry can be put back' do
    entry = @entries.first

    entry.update!(status: :withdrawn)

    visit entries_admin_submission_request_path(@request)

    check "Select #{entry.entry_id}"
    select 'Accession issued', from: 'bulk_row[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated 1'
    assert_equal 'accession_issued', entry.reload.status
    assert_not entry.retracted?
  end
end

