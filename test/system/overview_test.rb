require 'application_system_test_case'

# The Overview tab: what a curator is told is next, what they are offered
# to do about it, and which fields the curation rail puts in front of
# them. What those actions then do to the database is
# test/integration/admin/{accessions,curations}_test.rb.
class OverviewSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @req        = @submission.request
  end

  # --- the next action -----------------------------------------------------

  test 'a project with no accession is offered one, named and counted' do
    projects(:primary).update!(accession: nil, status: 'curating')

    visit admin_submission_request_path(@req)

    assert_text 'eligible for accession issuance'
    assert_link 'Issue PRJDB for 1 project'
  end

  # What to *say* is a priority question; what a curator is *allowed to
  # do* is not. An unread message outranks issuance in the banner, and
  # used to take the button with it — leaving a BP request with no way to
  # issue at all.
  test 'a question from the submitter leads the banner without taking the button away' do
    projects(:primary).update!(accession: nil, status: 'curating')
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'a question')

    visit admin_submission_request_path(@req)

    assert_text 'waiting for a reply'
    assert_link 'Issue PRJDB for 1 project'
  end

  test 'a project that already has an accession is not offered another' do
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    visit admin_submission_request_path(@req)

    assert_no_link 'Issue PRJDB for 1 project'
    assert_text 'PRJDB000001'
  end

  # Offering a button the service would refuse just turns into an error
  # flash — say nothing is pending instead.
  test 'a status that cannot be issued from offers nothing rather than a button that fails' do
    projects(:primary).update!(accession: nil, status: 'public')

    visit admin_submission_request_path(@req)

    assert_no_link 'Issue PRJDB for 1 project'
    assert_text 'Nothing is waiting on a curator'
  end

  test 'a BioSample submission whose samples are all released offers nothing either' do
    submissions(:biosample).samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('public'))

    visit admin_submission_request_path(submission_requests(:biosample))

    assert_no_link 'Issue SAMD for 2 samples'
    assert_text 'Nothing is waiting on a curator'
  end

  # A refused issuance writes no CurationEvent — the service raises before
  # recording one — so without the activity feed carrying it, the only
  # trace would be a row whose page nothing links to. The bulk action's
  # "each reports on its own request" depends on this being here.
  test 'a refused issuance is readable on the request it was about' do
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    perform_enqueued_jobs do
      @submission.accession_issuances.create!(actor: 'admin:bob', started_at: Time.current)
                 .then { IssueAccessionsJob.perform_later(issuance_id: it.id) }
    end

    visit admin_submission_request_path(@req)

    assert_text 'could not issue accessions'
    assert_text 'already has accession'
  end

  # --- what the summary says -----------------------------------------------

  test 'an unissued project says so rather than leaving the field blank' do
    projects(:primary).update!(accession: nil)

    visit admin_submission_request_path(@req)

    assert_text '— (not issued)'
  end

  test 'a BioSample submission names the first accession and counts the rest' do
    samples(:first).update!(accession: 'SAMD00000001')
    samples(:second).update!(accession: 'SAMD00000002')

    visit admin_submission_request_path(submission_requests(:biosample))

    assert_text 'SAMD00000001'
    assert_text '+1 more'
  end

  # --- the curation rail ---------------------------------------------------

  test 'the rail puts the whole decision in one form' do
    seed_chain

    visit admin_submission_request_path(@req)

    assert_field  'Status'
    assert_field  'Assignee'
    assert_field  'Hold date'
    assert_field  'Curator comment'
    assert_button 'Save'
  end

  # `submission.hold_date` is a v3 field for any DB, but only BioProject
  # projects it onto a column, syncs it, or notifies on it. Offering the
  # field elsewhere would report "saved" for something nothing honours.
  test 'the hold date is offered for BioProject only' do
    submission = submissions(:biosample)
    submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'hold_date' => '2026-12-31'}},
      actor: 'test-seed', source: :manual
    )

    visit admin_submission_request_path(submission.request)

    assert_field    'Curator comment'
    assert_no_field 'Hold date'
  end

  # The comment is a typed column, independent of the chain, so it stays
  # editable when the record cannot be replayed — but the hold-date input
  # must disappear rather than offer to overwrite a value it cannot show.
  test 'the hold date disappears when the record cannot be replayed' do
    visit admin_submission_request_path(@req)

    assert_field    'Curator comment'
    assert_no_field 'Hold date'
  end

  private

  def seed_chain
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}]}},
      actor: 'test-seed', source: :manual
    )
  end
end
