require 'application_system_test_case'

# What the ledger says after a bulk press.
#
# The flash it replaces said "Sent 19 accession(s)" and was gone on the
# next click — which is the click a curator makes to check. Two things it
# could never say: which of the ticked submissions did nothing, and what
# the numbers actually were.
class AccessionSummarySystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @run = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: Time.current,
                                        origin: 'All requests (2 submissions)')
  end

  # Mirrors what IssueAccessionsJob writes: a completed row has attempted
  # a mail and recorded what became of it, and nothing else has.
  def issue(submission, status: 'completed', **attrs)
    settled = {}

    settled[:finished_at] = Time.current unless AccessionIssuance.new(status:).loading?
    settled[:mail_status] = 'sent'       if status == 'completed'

    @run.issuances.create!(submission:, actor: @run.actor, started_at: Time.current,
                           status:, **settled, **attrs)
  end

  test 'the numbers that were allocated are on the ledger, not one click away' do
    issue(submissions(:bioproject), accessions: %w[PRJDB19940])
    issue(submissions(:biosample), accessions: (412_919..412_936).map { format('SAMD%08d', it) })

    visit admin_submission_requests_path

    within '[data-test-issuance-summary]' do
      assert_text '19 accessions issued'
      assert_text 'PRJDB19940 issued'

      # A range, so "did they really get numbers" is answerable here
      # rather than eighteen lines down a detail page.
      assert_text '18 samples now accession_issued'
      assert_text 'SAMD00412919–936'

      assert_text '2 notification mails sent'
    end
  end

  # The point of the pair. A submission that was ticked and did nothing
  # is invisible in any count of what happened.
  test 'a submission that was selected but did nothing is named with its reason' do
    issue(submissions(:bioproject), accessions: %w[PRJDB19940])
    issue(submissions(:biosample), status: 'refused', error_message: 'Project status public is not issuable.')

    visit admin_submission_requests_path

    within '[data-test-issuance-summary]' do
      assert_text 'Unchanged'
      assert_text 'skipped, Project status public is not issuable.'
      assert_text 'No mail was sent for this submission'
    end
  end

  # A press where every submission was skipped. "0 accessions issued"
  # reads as a broken counter, and this is the case a curator most needs
  # to understand: they ticked things and got nothing.
  test 'a run that allocated nothing says so rather than counting to zero' do
    issue(submissions(:bioproject), status: 'refused', error_message: 'Project status public is not issuable.')

    visit admin_submission_requests_path

    within '[data-test-issuance-summary]' do
      assert_text    'Nothing was issued'
      assert_no_text '0 accessions issued'
      assert_text    'Project status public is not issuable.'
    end
  end

  test 'the summary stays until it is dismissed' do
    issue(submissions(:bioproject), accessions: %w[PRJDB19940])

    visit admin_submission_requests_path
    assert_selector '[data-test-issuance-summary]'

    # A reload is what kills a flash, and the reason this is not one.
    visit admin_submission_requests_path
    assert_selector '[data-test-issuance-summary]'

    click_button 'Dismiss'

    assert_no_selector '[data-test-issuance-summary]'
    assert_current_path admin_submission_requests_path
  end

  # "What did the thing I just did do" — someone else's press is not it,
  # and would be noise on a screen that exists to be checked once.
  test 'another curator run is not on my ledger' do
    issue(submissions(:bioproject), accessions: %w[PRJDB19940])
    @run.update!(actor: 'admin:dave')

    visit admin_submission_requests_path

    assert_no_selector '[data-test-issuance-summary]'
  end

  test 'a run still going says so and links to itself' do
    issue(submissions(:bioproject), accessions: %w[PRJDB19940])
    issue(submissions(:biosample), status: 'queued')

    visit admin_submission_requests_path

    within '[data-test-issuance-summary]' do
      assert_text 'Issuing 1 accession… 1 of 2 done'
      assert_link "Run ##{@run.id}"
    end
  end
end
