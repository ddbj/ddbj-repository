require 'test_helper'

# What issuance does once nobody is waiting for it: allocates, stamps,
# records, and reports the outcome — including the outcomes that are not
# failures.
class IssueAccessionsJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    Sequence.ensure_records!
  end

  def issuance_for(submission, targeting: {})
    submission.accession_issuances.create!(actor: 'admin:bob', targeting:, started_at: Time.current)
  end

  test 'a BioProject issuance stamps the project and names the accession' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance = issuance_for(submission)

    IssueAccessionsJob.perform_now(issuance_id: issuance.id)

    issuance.reload

    assert issuance.completed_status?
    assert_equal 1, issuance.accessions.size
    assert_match(/\APRJDB\d+\z/,   issuance.accessions.first)
    assert_equal 'accession_issued', projects(:primary).reload.status
    assert_not_nil issuance.finished_at
  end

  test 'a BioSample issuance covers every eligible sample' do
    submission = submissions(:biosample)
    submission.samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))

    IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)

    assert_empty submission.samples.where(accession: nil)
  end

  # The filter is re-derived here, not resolved when the button was
  # pressed — which is what makes "all N matching the filter" mean what
  # it says at 100K rows.
  test 'a filtered targeting is resolved when the job runs' do
    submission = submissions(:biosample)
    submission.samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))
    samples(:second).update!(status: 'public')

    issuance = issuance_for(submission, targeting: {scope: 'filtered', filter: {status: %w[curating]}})

    IssueAccessionsJob.perform_now(issuance_id: issuance.id)

    assert_not_nil samples(:first).reload.accession
    assert_nil     samples(:second).reload.accession, 'the filter excluded it'
  end

  test 'a selected targeting touches only the ticked rows' do
    submission = submissions(:biosample)
    submission.samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))

    issuance = issuance_for(submission, targeting: {scope: 'selected', ids: [samples(:first).id]})

    IssueAccessionsJob.perform_now(issuance_id: issuance.id)

    assert_not_nil samples(:first).reload.accession
    assert_nil     samples(:second).reload.accession
  end

  # A refusal is the service declining for a reason it can state. It is
  # not a failure, and rendering it as one would train curators to ignore
  # the red box.
  test 'a refusal is recorded as such, with its reason' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    issuance = issuance_for(submission)

    IssueAccessionsJob.perform_now(issuance_id: issuance.id)

    issuance.reload

    assert issuance.refused_status?
    assert_match(/already has accession/, issuance.error_message)
    assert_empty issuance.accessions
  end

  # The distinction the run page reads: Skipped is grey and means a rule
  # said no; Failed is red and means somebody has to look. A chain that
  # cannot replay used to arrive as the first, so a corrupt submission
  # sat in the queue looking merely ineligible and nobody was told.
  # Subscribed for the block and taken off again: Rails.error's
  # subscribers are global, and one left behind keeps collecting for
  # every test after this one.
  def capture_error_reports
    reports    = []
    subscriber = Class.new { define_method(:report) {|error, **| reports << error } }.new

    Rails.error.subscribe(subscriber)

    begin
      yield
    ensure
      Rails.error.unsubscribe(subscriber)
    end

    reports
  end

  test 'a broken chain fails and is reported, rather than reading as skipped' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    SubmissionUpdate.create_with_patch!(
      submission:, patch_json: 'not-json', db: 'bioproject', status: :applied,
      actor: 'test', source: :manual, patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    issuance = issuance_for(submission)
    reports  = capture_error_reports { IssueAccessionsJob.perform_now(issuance_id: issuance.id) }

    issuance.reload

    assert     issuance.failed_status?
    assert_not issuance.refused_status?
    assert_match(/patch chain is unreadable/, issuance.error_message)
    assert_nil projects(:primary).reload.accession, 'nothing was issued'

    assert reports.any? { it.is_a?(AccessionIssue::ChainBroken) },
           'a broken chain has to reach whoever can repair it'
  end

  # The mail is enqueued after the transaction commits, so it can fail on
  # its own — and losing the accessions from the record because of it
  # would have the run page deny numbers that exist and cannot be handed
  # back. The numbers are the outcome; the notification is a consequence.
  test 'a mail that cannot be queued does not erase the accessions it was about' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance = issuance_for(submission)
    reports  = capture_error_reports {
      AccessionMailer.stub(:with, ->(**) { raise ActiveRecord::ConnectionNotEstablished, 'queue is down' }) do
        IssueAccessionsJob.perform_now(issuance_id: issuance.id)
      end
    }

    issuance.reload

    assert     issuance.completed_status?, 'the accessions committed, so the row has to say so'
    assert_not issuance.accessions.empty?, 'the numbers must survive the notification'
    assert_equal projects(:primary).reload.accession, issuance.accessions.sole
    assert_match(/queue is down/, issuance.error_message)

    assert reports.any? { it.is_a?(ActiveRecord::ConnectionNotEstablished) },
           'a submitter nobody could tell has to reach somebody'
  end

  # The other half: nothing that runs after the commit may overwrite the
  # outcome. participate! touches a FK, and a curator deleted mid-run
  # would otherwise turn a successful issuance into "failed, nothing
  # issued".
  test 'a failure after the completion write leaves the outcome alone' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance = issuance_for(submission)

    SubmissionRequestParticipant.stub(:insert_all, ->(*, **) { raise 'boom' }) do
      IssueAccessionsJob.perform_now(issuance_id: issuance.id)
    end

    issuance.reload

    assert     issuance.completed_status?
    assert_not issuance.accessions.empty?
  end

  test 'a second issuance is refused while another is actually running' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance_for(submission).update!(status: 'running')
    second = issuance_for(submission)

    IssueAccessionsJob.perform_now(issuance_id: second.id)

    assert second.reload.refused_status?
    assert_match(/already running/, second.error_message)
    assert_nil projects(:primary).reload.accession, 'nothing was issued'
  end

  # A double-click makes two rows before either job starts. Counting a
  # queued row as running would have each see the other and refuse, so
  # nothing would be issued and both pages would blame the other.
  test 'a double-click issues once rather than deadlocking into two refusals' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    first  = issuance_for(submission)
    second = issuance_for(submission)

    IssueAccessionsJob.perform_now(issuance_id: first.id)
    IssueAccessionsJob.perform_now(issuance_id: second.id)

    assert first.reload.completed_status?
    assert second.reload.refused_status?
    assert_not_nil projects(:primary).reload.accession
  end

  # A worker killed mid-issuance leaves a `running` row nothing clears.
  # Without a bound it would latch the submission shut for good.
  test 'a running row older than the bound no longer blocks' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance_for(submission).update!(status: 'running', started_at: (AccessionIssuance::STALE_AFTER + 1.hour).ago)

    IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)

    assert_not_nil projects(:primary).reload.accession
  end

  # Widening a handful of checked rows into all 100K is the irreversible
  # direction once the Sequence has moved. A targeting nothing recognises
  # is a fault, not a refusal — it means something wrote a shape we do
  # not understand — so it lands as `failed` and is reported.
  test 'an unrecognised targeting fails rather than targeting everything' do
    submission = submissions(:biosample)
    submission.samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))

    issuance = issuance_for(submission, targeting: {scope: 'everything'})

    IssueAccessionsJob.perform_now(issuance_id: issuance.id)

    assert issuance.reload.failed_status?
    assert_match(/Unknown target/, issuance.error_message)
    assert_equal 2, submission.samples.where(accession: nil).count, 'nothing was issued'
  end

  # Issuing is editing, so it puts the curator in the request's
  # participants — but only once it has actually happened.
  test 'a completed issuance makes the curator a participant, a refused one does not' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)

    assert_equal [users(:bob)], submission.request.reload.participants

    projects(:primary).update!(accession: 'PRJDB000001')
    submission.request.participations.destroy_all

    IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)

    assert_empty submission.request.reload.participants
  end

  # `/**/accession` is ordinary record content since ddbj-canon/v2, so
  # issuance appends a patch — and the event says in words what the patch
  # did, pointing at it so the feed shows one line rather than two.
  test 'issuance leaves both a patch and an event that names it' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.append_update!({'schema_version' => 'v3', 'project' => {'title' => 'x'}}, actor: 'test')

    assert_difference ['CurationEvent.count', 'submission.updates.count'], 1 do
      IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)
    end

    event = CurationEvent.last

    assert_equal 'accession_issued',         event.action
    assert_equal 'admin:bob',                event.actor
    assert_equal 'issued 1 PRJDB accession (PRJDB1)', event.summary
    assert_not_nil event.submission_update
  end

  test 'a refused issuance records nothing' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'public')

    assert_no_difference 'CurationEvent.count' do
      IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)
    end
  end

  test 'the submitter is emailed once the accessions exist' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    assert_enqueued_emails 1 do
      IssueAccessionsJob.perform_now(issuance_id: issuance_for(submission).id)
    end
  end
end
