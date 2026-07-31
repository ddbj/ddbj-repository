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

    issuance = issuance_for(submission, targeting: {scope: 'selected', sample_ids: [samples(:first).id]})

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

  test 'a second issuance on the same submission is refused while the first runs' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    issuance_for(submission) # left running
    second = issuance_for(submission)

    IssueAccessionsJob.perform_now(issuance_id: second.id)

    assert second.reload.refused_status?
    assert_match(/already running/, second.error_message)
    assert_nil projects(:primary).reload.accession, 'nothing was issued'
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
    assert_equal 'issued 1 PRJDB accession', event.summary
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
