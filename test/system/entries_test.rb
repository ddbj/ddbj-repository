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

    # Not `@request`: ActionDispatch::IntegrationTest, which this
    # inherits from, replaces that ivar with its own ActionDispatch::
    # Request the moment a request is performed — and a path built from it
    # afterwards names nothing, as a 404 rather than as an error.
    @req = request.reload
    @entries = @req.submission.entries.order(:id).to_a
  end

  # The tab is one slot named for what the submission's rows are. A
  # BioProject has no bag of anything and gets neither name.
  test 'the rows tab is called Entries for an ST.26 submission' do
    visit admin_submission_request_path(@req)

    assert_link 'Entries'
    assert_no_link 'Samples'

    click_link 'Entries'

    assert_selector 'h2', text: 'Entries'
    assert_text @entries.first.accession
    assert_text @entries.first.entry_id
  end

  test 'the entries can be narrowed to the one being fixed' do
    visit entries_admin_submission_request_path(@req)

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
    visit entries_admin_submission_request_path(@req)

    check "Select #{@entries.first.entry_id}"
    select 'Withdrawn', from: 'bulk_row[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated 1'
    assert_equal 'withdrawn', @entries.first.reload.status
    assert_equal 'accession_issued', @entries.second.reload.status
  end

  test 'the status filter finds what was retracted' do
    @entries.first.update!(status: :canceled)

    visit entries_admin_submission_request_path(@req, status: 'canceled')

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
    @req.submission.entries.update_all(status: Lifecycleable::STATUSES.fetch('public'))

    state = CurationState.new(@req.reload)

    assert_equal 2, state.row_count, 'the entries are the rows now'
    assert state.curated?

    visit admin_submission_request_path(@req)

    within '.workbench-progress' do
      assert_text 'Public'
    end
  end

  # ST.26 entries are created with their accession, so there is never
  # anything to issue — the ledger has to say so rather than offer a
  # button that allocates nothing.
  test 'there is nothing to issue accessions for' do
    plan = AccessionPlan.for([@req.submission])

    assert_equal 0, plan.items.sole.issuable
  end

  # Withdrawing an entry keeps it out of the flatfile, so a curator who
  # did it in error has to be able to undo it. Leaving the state an entry
  # starts in off the settable list made retraction one-way.
  test 'a withdrawn entry can be put back' do
    entry = @entries.first

    entry.update!(status: :withdrawn)

    visit entries_admin_submission_request_path(@req)

    check "Select #{entry.entry_id}"
    select 'Accession issued', from: 'bulk_row[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated 1'
    assert_equal 'accession_issued', entry.reload.status
    assert_not entry.retracted?
  end
  # The flatfile is a stored file, so retracting an entry does not touch
  # it. The rule was on the screen and the way to act on it was not: the
  # only regeneration was a bulk tool reached from elsewhere and driven
  # by a paste of accession numbers.
  test 'retracting an entry offers the regeneration that acts on it' do
    visit entries_admin_submission_request_path(@req)

    assert_text 'left out of the flatfile the next time it is generated'
    assert_no_button 'Regenerate this flatfile'

    @entries.first.update!(status: :canceled)

    visit entries_admin_submission_request_path(@req)

    assert_text '1 entry here is canceled or withdrawn'
    assert_text 'The flatfile on record was written before the last of them'
    assert_button 'Regenerate this flatfile'

    # The part that surprises: the file is rebuilt rather than edited, so
    # it comes back as today's rules would write it, and the record is
    # written back with it.
    assert_text 'picks up any change to how the two are written'

    assert_difference 'RegenerateFlatfilesRun.count', 1 do
      click_button 'Regenerate this flatfile'
    end

    run = RegenerateFlatfilesRun.order(:id).last

    # This submission, named as itself, and no date moved: the press is
    # about what the file contains.
    assert_equal 'submission',    run.target
    assert_equal @req.submission, run.submission
    assert_equal 1,               run.total
    assert_nil   run.locus_date
    assert_empty run.numbers.to_a

    # The run's own page, which is where the answer to "did it work" is,
    # and which offers the way back to the request it was pressed from.
    assert_current_path admin_regenerate_flatfiles_run_path(run)
    assert_link "Back to request ##{@req.id}"
  end

  # Otherwise the panel states a condition rather than a discrepancy, and
  # never clears: "1 entry is canceled" is true for ever, and the curator
  # has no way to tell an unregenerated file from a regenerated one.
  test 'the offer clears once the flatfile has been written since' do
    @entries.first.update!(status: :canceled)

    run = RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'submission', submission: @req.submission,
                                        total: 1, started_at: Time.current)

    RegenerateSubmissionFlatfilesJob.perform_now @req.submission, users(:bob), run, nil

    visit entries_admin_submission_request_path(@req)

    assert_text '1 entry here is canceled or withdrawn'
    assert_text 'already leaves them out'
    assert_no_button 'Regenerate this flatfile'
  end

  # One run at a time, over every scope — and the reason a press would be
  # refused belongs where the press is, not on a screen this curator has
  # never seen.
  test 'a run already in flight names itself and disables the press' do
    @entries.first.update!(status: :canceled)

    RegenerateFlatfilesRun.create!(actor: 'admin:someone', target: 'all', total: 10, started_at: 2.minutes.ago)

    visit entries_admin_submission_request_path(@req)

    assert_text 'The regeneration run started at'
    assert_button 'Regenerate this flatfile', disabled: true
  end

  # Of the whole submission, not of the page: a curator who has narrowed
  # to one entry has not narrowed what goes out.
  test 'the count is of the submission, not of the filter' do
    @entries.first.update!(status: :canceled)

    visit entries_admin_submission_request_path(@req, q: @entries.last.entry_id)

    within '[data-test-retracted-entries]' do
      assert_text '1 entry here is canceled or withdrawn'
    end
  end
end
