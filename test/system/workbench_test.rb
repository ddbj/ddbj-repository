require 'application_system_test_case'

# The four workbench tabs, walked the way a curator walks them: one
# screen answers one question, and the summary bar stays put across all
# of them.
class WorkbenchSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

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

    # Addressed by what the rail actually is, not by a path built from an
    # id that could never be a submission's — that selector could not
    # have matched whatever the page rendered.
    assert_no_button 'Save changes'
    assert_no_selector "form[action$='/curation']"
  end

  test 'the samples tab narrows to the group being worked on' do
    visit samples_admin_submission_request_path(@req)

    assert_text 'fixture-sample-1'
    assert_text 'fixture-sample-2'

    # What the curator is deciding from: the accession, what it is, and
    # where it is — not just the identifier.
    within 'tbody tr', text: 'fixture-sample-1' do
      assert_text 'SAMD00000001'
      assert_text 'Generic.1.0'  # package
      assert_text 'private'      # status
    end

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

    # The page param is namespaced so it cannot collide with a future
    # paginator wanting plain `?page=`. pagy silently ignores a wrong
    # `page_key` shape, so the only evidence is in the links themselves.
    assert_selector "a[href*='samples_page=']"
    assert_no_selector "a[href*='?page=']"

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

  # Reading is not dealing with it — and it never was on anyone else's
  # behalf. Opening the tab used to mark the thread read for EVERY
  # curator, so a colleague glancing at it took the request out of the
  # assignee's queue as well as their own.
  test 'reading the thread leaves it in the queue until this curator says otherwise' do
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit admin_submission_request_path(@req)
    click_link 'Messages'

    assert_text 'Please advise'
    assert_equal 1, @req.unread_message_count_for(users(:bob)), 'looking is not knowing'

    click_button 'Mark 1 message as read'

    assert_text 'Marked as read.'
    assert_equal 0, @req.unread_message_count_for(users(:bob))
  end

  # "Here is the corrected file" is most of what this conversation is
  # for, and it was the one thing the thread could not carry. Sent with
  # no prose, because that is a real message.
  test 'a message can be nothing but a file' do
    file = @req.messages.new
    file.files.attach(io: StringIO.new("sample_name\torganism\n"), filename: 'samples.tsv',
                      content_type: 'text/tab-separated-values')
    file.assign_attributes(user: users(:bob), author_role: 'curator', body: '')
    file.save!

    visit messages_admin_submission_request_path(@req)

    assert_link 'samples.tsv'
  end

  # Everyone following is told, not everyone who has posted. A curator
  # copied in has not posted, and the mail that copied them in promises
  # replies will reach them.
  test 'a copied-in colleague is mailed the submitter reply too' do
    @req.subscribe!(users(:dave))

    reply = @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'answered')
    mail  = SubmissionMessageMailer.with(message: reply).notify_curators

    assert_includes Array(mail.to), users(:dave).email
  end

  # No size validation, deliberately — but "no limit" is only true
  # because the file never travels through this form. `direct_upload`
  # is what makes that so, and losing it would put every attachment
  # behind an upstream body limit that is not ours to raise.
  test 'the attachment field uploads straight to storage' do
    visit messages_admin_submission_request_path(@req)

    assert_selector 'input[type=file][data-direct-upload-url]', visible: :all
  end

  # "Leave as-is" means the same as not touching the select, so it is only
  # offered where there is nothing to preselect: a BioSample submission
  # whose samples disagree on status. Assignee cannot disagree, and there
  # the option sat directly above "— Unassigned —" — two dashed, neutral
  # entries, one a no-op and the other a real change.
  test 'leave as-is is offered only where there is no value to preselect' do
    # Rows that agree, so the status field has something to preselect.
    @req.submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('curating'))

    visit admin_submission_request_path(@req)

    within '[data-test-curator-edit]' do
      assert_no_select 'curation[status]', with_options: ['— Leave as-is —']

      # Assignee never needs it: one column on the request, always a value
      # to preselect — and the option sat directly above "— Unassigned —".
      assert_no_select 'curation[assignee_id]', with_options: ['— Leave as-is —']
      assert_select    'curation[assignee_id]', selected: '— Unassigned —'
    end
  end

  # Where the samples disagree there is nothing to preselect, and leaving
  # the field alone has to mean leaving the mixture alone.
  test 'a submission whose rows disagree opens on leave as-is' do
    assert_nil CurationState.new(@req).uniform_status, 'the fixture is mixed'

    visit admin_submission_request_path(@req)

    within '[data-test-curator-edit]' do
      assert_select 'curation[status]', with_options: ['— Leave as-is —']
    end
  end

  # Copying somebody in adds them to the notifications from here on, and
  # that is all it does — this thread is the curator's conversation with
  # the submitter, not a way to put work to another curator. So there is
  # nothing a tick could mean for somebody already following, and leaving
  # the box blank would read as a list to fill in on every message.
  test 'a colleague already following is shown as already covered' do
    @req.subscribe!(users(:dave))

    visit messages_admin_submission_request_path(@req)

    assert_selector "input[type=checkbox][value='#{users(:dave).id}'][checked][disabled]", visible: :all
  end

  # And the claim has to be true. A curator's message used to reach
  # nobody but the submitter, so a colleague following the request learned
  # nothing when it was answered — and since answering settles the thread,
  # it left their queue at the same moment.
  test 'a colleague following is mailed when somebody else answers' do
    @req.subscribe!(users(:dave))

    visit messages_admin_submission_request_path(@req)
    fill_in 'submission_message[body]', with: 'Answering this one.'

    perform_enqueued_jobs { click_button 'Send message' }

    told = ActionMailer::Base.deliveries.find { it.subject.include?('replied to the submitter') }

    assert_not_nil told
    assert_includes Array(told.to), users(:dave).email
  end

  # What a curator does in mail without thinking about it. Without it the
  # only way to bring a colleague in is to tell them out of band, at which
  # point the thread stops being the record of who was asked what.
  test 'copying a colleague in tells them and starts them following' do
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit messages_admin_submission_request_path(@req)

    fill_in 'submission_message[body]', with: 'Looping in dave.'
    check 'dave'

    assert_emails 2 do
      click_button 'Send message'
    end

    assert_text 'dave copied in'

    # The thread says who was asked. The subscription it created is
    # invisible from here, so without this the record is incomplete.
    assert_text 'copied in dave'

    assert @req.reload.following?(users(:dave))
  end

  # Being copied in has to arrive as mail, not only as a subscription. A
  # curator who has just replied leaves nothing unanswered, so the queue
  # would say nothing about it until the submitter writes back — which
  # may be never, and is not when they were asked to look.
  test 'a colleague copied in is told now, not when the submitter next writes' do
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit messages_admin_submission_request_path(@req)
    fill_in 'submission_message[body]', with: 'Have a look.'
    check 'dave'

    perform_enqueued_jobs { click_button 'Send message' }

    copied = ActionMailer::Base.deliveries.find { it.subject.include?('copied you in') }

    assert_not_nil copied
    assert_includes Array(copied.to), users(:dave).email
  end

  # Following without saying anything: watch what happens next without
  # replying, editing, or otherwise leaving a mark on somebody else's
  # request. A subscription you can only get by replying is one nobody
  # knows they have.
  test 'a curator can follow a request without touching it' do
    @req.update_column(:assignee_id, users(:dave).id)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit admin_submission_request_path(@req)

    assert_no_text 'following bob'

    click_button 'Follow'

    assert_text 'Following this request'
    assert_text 'following bob'
    assert_empty @req.messages.curator_role, 'watching is not speaking'

    visit admin_root_path
    within('[data-test-section="involved"]') { assert_text "##{@req.id}" }
  end

  # The summary bar is where the request's facts are, so it must not go
  # on naming somebody who said they were done.
  test 'the summary bar names who is following, not who once was' do
    @req.update_column(:assignee_id, users(:dave).id)
    @req.subscribe!(users(:bob))

    visit admin_submission_request_path(@req)
    assert_text 'following bob'

    click_button 'Stop following'

    assert_no_text 'following bob'
    assert_includes @req.reload.participants, users(:bob), 'they were still here'
  end

  # Acting on somebody else's request follows it from then on, which is
  # usually right and occasionally not. A queue nobody can put things
  # down in stops being read.
  test 'a curator can stop following a request they were drawn into' do
    @req.update_column(:assignee_id, users(:dave).id)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')
    @req.subscribe!(users(:bob))

    visit admin_root_path
    within('[data-test-section="involved"]') { assert_text "##{@req.id}" }

    visit admin_submission_request_path(@req)
    click_button 'Stop following'

    assert_text 'No longer following'

    visit admin_root_path
    within('[data-test-section="involved"]') { assert_no_text "##{@req.id}" }

    # The work itself is untouched: it is still somebody's, and the
    # participation still records that this curator was here.
    assert_includes @req.reload.participants, users(:bob)
    assert_equal users(:dave), @req.assignee
  end

  # Owning it is not a subscription you can decline.
  test 'the assignee is not offered a way to stop following' do
    @req.update_column(:assignee_id, users(:bob).id)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')

    visit admin_submission_request_path(@req)

    assert_no_button 'Stop following'
  end

  # Stepping back in is stepping back in.
  test 'replying follows a request again' do
    @req.update_column(:assignee_id, users(:dave).id)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')
    @req.unsubscribe!(users(:bob))

    visit messages_admin_submission_request_path(@req)
    fill_in 'submission_message[body]', with: 'Taking a look.'
    click_button 'Send message'

    assert @req.reload.following?(users(:bob))
  end

  # The whole point of the marker: one curator dealing with it does not
  # speak for the others.
  test 'a colleague marking it read does not clear this curator queue' do
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'Please advise')
    @req.mark_read_by!(users(:dave))

    assert_equal 0, @req.unread_message_count_for(users(:dave))
    assert_equal 1, @req.unread_message_count_for(users(:bob))
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

# The record, laid out for reading.
#
# Curators were shown the raw JSON, which is the whole record and
# unreadable. The ask was for the whole thing, legible — so the layout
# follows the shape of the data and names no field, and the assertions
# here follow the same rule: one that named `project.title` would carry
# the same obligation to the schema the screen was written to avoid.
class RecordOutlineSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @request    = submission_requests(:bioproject)
    @submission = @request.submission
  end

  def with_record(record)
    @submission.append_update!(record, actor: 'test')
    yield
  end

  test 'the record is readable without opening the JSON' do
    with_record({'project' => {'title' => 'A study of things', 'hold_date' => '2026-12-01'}}) do
      visit record_admin_submission_request_path(@request)

      within '[data-test-record-section="project"]' do
        assert_text 'title'
        assert_text 'A study of things'
        assert_text 'hold_date'
      end

      # Not instead of the JSON — that is what somebody reaches for when
      # they need to see exactly what is stored.
      assert_link 'View as JSON'
    end
  end

  test 'repeated records are a table, and a long one says what it is not showing' do
    samples = Array.new(40) {|i| {'alias' => "S#{i}", 'organism' => 'Homo sapiens'} }

    with_record({'samples' => samples}) do
      visit record_admin_submission_request_path(@request)

      within '[data-test-record-section="samples"]' do
        assert_selector 'th', text: 'alias'
        assert_selector 'th', text: 'organism'
        assert_text 'S0'

        # Twenty rows out of forty look like forty unless it says so.
        assert_selector '[data-test-record-truncated]', text: 'Showing 20 of 40'
      end
    end
  end

  # The screen has no field list, so a key nobody has taught it about
  # still appears. This is the whole reason it is written this way.
  test 'a field the screen has never heard of shows up anyway' do
    with_record({'project' => {'some_future_field' => 'from a later schema'}}) do
      visit record_admin_submission_request_path(@request)

      within '[data-test-record-section="project"]' do
        assert_text 'some_future_field'
        assert_text 'from a later schema'
      end
    end
  end

  # A record too big to lay out used to make the section disappear, which
  # a curator cannot tell from the feature not being deployed — and the
  # records that reach the limit are the ones least readable as JSON.
  test 'a record too large to lay out says so rather than vanishing' do
    with_record({'project' => {'description' => 'x' * (Admin::SubmissionDetail::CANONICAL_DISPLAY_SIZE_LIMIT + 1024)}}) do
      visit record_admin_submission_request_path(@request)

      within '[data-test-record-outline]' do
        assert_selector '[data-test-record-too-large]', text: 'Not laid out'
      end

      assert_link 'View as JSON'
    end
  end

  # v3 gives every database the same keys, so which ones are present is
  # itself the answer to "does this record have sequences?" — otherwise a
  # question answered by scrolling.
  test 'the record says what it carries before it says what is in it' do
    with_record({'project' => {'title' => 'x'}, 'relations' => %w[PRJDB1]}) do
      visit record_admin_submission_request_path(@request)

      within '[data-test-record-carries]' do
        assert_link 'project'
        assert_link 'relations'
        assert_text "2 of the #{RecordOutline.schema_key_count} v3 keys"
      end
    end
  end

  # Browser search answers "not here" for a value that is in the record
  # and not on the page, so the omission has to carry its destination
  # where the reader is rather than only at the top of the card.
  test 'a truncated collection says where the rest is' do
    with_record({'samples' => Array.new(40) {|i| {'alias' => "S#{i}"} }}) do
      visit record_admin_submission_request_path(@request)

      assert_selector '[data-test-record-truncated]', text: 'in the tabs above or in the JSON below'
    end
  end
end
