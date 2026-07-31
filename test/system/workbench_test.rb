require 'application_system_test_case'

# The four workbench tabs, walked the way a curator walks them: one
# screen answers one question, and the summary bar stays put across all
# of them.
class WorkbenchSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @req = submission_requests(:biosample)
  end

  test 'the tabs each answer their own question, and the summary bar survives all of them' do
    visit admin_submission_request_path(@req)

    assert_text "##{@req.id}"
    assert_text 'BioSample'
    assert_text 'Accession issued' # the progress step

    click_link 'Samples'
    assert_text 'fixture-sample-1'
    assert_text "##{@req.id}" # the summary bar follows the tabs

    click_link 'Messages'
    assert_text "##{@req.id}"

    click_link 'Record & history'
    assert_text 'Patch chain'
    assert_text 'Engineering details'
    assert_text 'Canonical version'

    click_link 'Overview'
    assert_text 'Curation'
  end

  # Before Apply there is no submission, so the curation rail has nothing
  # to edit — the screen still has to open rather than assume one.
  test 'a request with no submission still opens, without a curation rail' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    attach_ddbj_record(request)
    request.save!

    visit admin_submission_request_path(request)

    assert_text "##{request.id}"
    assert_no_button 'Save curation'
    assert_no_selector "form[action='#{admin_submission_curation_path(request.id)}']"
  end

  test 'the samples tab narrows to the group being worked on' do
    visit samples_admin_submission_request_path(@req)

    assert_text 'fixture-sample-1'
    assert_text 'fixture-sample-2'

    fill_in 'Search', with: 'sample-1'
    click_button 'Filter'

    assert_text    'fixture-sample-1'
    assert_no_text 'fixture-sample-2'

    click_link 'Clear'

    select 'Not issued', from: 'Accession'
    click_button 'Filter'

    assert_no_text 'fixture-sample-1' # the fixture's accessioned one
    assert_text    'fixture-sample-2'
  end

  # A submission can carry 100K samples, so the tab pages — and the page
  # links have to carry the filter, or clicking page 2 silently widens
  # the set back to everything.
  test 'the samples tab pages, and paging keeps the filter' do
    60.times {|i| @req.submission.samples.create!(sample_name: "probe-#{format('%03d', i)}", status: :curating) }

    visit samples_admin_submission_request_path(@req)

    assert_selector 'tbody tr', count: 50
    assert_text '62 of 62 shown'

    select 'Curating', from: 'Status'
    click_button 'Filter'

    assert_text '60 of 62 shown'

    within '.pagination' do
      click_link '2'
    end

    assert_text '60 of 62 shown' # not 62 — the filter survived the page
    assert_selector 'tbody tr', count: 10
  end

  # A BP request has one project, not a bag of samples — the tab would
  # have nothing to show, so it hands the curator back to Overview.
  test 'the samples tab sends a BioProject request back to overview' do
    request = submission_requests(:bioproject)

    visit samples_admin_submission_request_path(request)

    assert_current_path admin_submission_request_path(request)
  end

  # Opening the thread is what marks it read, so the request stops
  # appearing in every curator's queue. Overview must not — the queue
  # entry has to survive until somebody actually looks.
  test 'reading the thread clears it from the queue, and glancing at Overview does not' do
    message = @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit admin_submission_request_path(@req)

    assert_nil message.reload.read_at

    click_link 'Messages'

    assert_text 'Please advise'
    assert_not_nil message.reload.read_at
  end
  # The Record tab is where a curator edits the parts of the record this
  # UI exposes — and only the parts that exist for that database.
  test 'the record tab offers the forms the database actually has' do
    bp = submissions(:bioproject)
    bp.append_update!(
      {'schema_version' => 'v3',
       'project'    => {'title' => 'A project'},
       'submission' => {'submitters' => [{'first_name' => 'Hanako', 'organizations' => [{'name' => 'NIG'}]}]}},
      actor: 'test-seed', source: :manual
    )

    visit record_admin_submission_request_path(bp.request)

    assert_text  'Project details'
    assert_field 'Title'
    assert_text  'Submitters'
    assert_field 'submitters[0][email]'

    # ST.26 has no Project row, so there is nothing for that form to edit.
    visit record_admin_submission_request_path(submission_requests(:st26))

    assert_no_text 'Project details'
  end
end

# Its own class: the shared setup signs a curator in, and "a submitter
# cannot get here" is only a claim about somebody who has not.
class WorkbenchAccessSystemTest < ApplicationSystemTestCase
  test 'a submitter is told they lack curator access rather than shown the workbench' do
    sign_in_as users(:carol), at: admin_submission_request_path(submission_requests(:biosample))

    assert_no_text 'Patch chain'
    assert_text 'curator'
  end
end
