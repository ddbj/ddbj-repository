require 'application_system_test_case'

# Every deployed environment restricts outgoing mail to DDBJ while
# sending to real submitters is still switched off. The banner states it
# once, because it is true of the environment rather than of any one
# action; a screen that claims a particular mail was sent has to answer
# for this one itself, which is what `mail_status` is for.
class MailRestrictionSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  test 'the restriction is on every admin screen while it is in force' do
    restrict_mail_to 'ddbj.nig.ac.jp', 'ursm.jp' do
      visit admin_root_path

      within '[data-test-mail-restricted]' do
        assert_text '@ddbj.nig.ac.jp'
        assert_text '@ursm.jp'
      end

      # Not the dashboard's own furniture: it has to hold wherever a
      # curator presses something that mails.
      visit admin_submission_requests_path

      assert_selector '[data-test-mail-restricted]'
    end
  end

  # And gone the moment the restriction is, or it becomes the notice
  # everybody has learned to read past.
  test 'nothing is claimed once mail goes out for real' do
    MailDomainAllowlistInterceptor.stub(:registered, nil) do
      visit admin_root_path

      assert_no_selector '[data-test-mail-restricted]'
    end
  end

  # The banner is a general warning; this is the one screen that would
  # otherwise contradict it. "sent 09:31" against an address the
  # interceptor threw away is the report telling a curator the submitter
  # has their accession numbers.
  test 'a run does not report a suppressed notification as sent' do
    run = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: Time.current,
                                       origin: 'All requests (2 submissions)')

    issued = ->(submission, mail_status) {
      run.issuances.create!(submission:, actor: run.actor, started_at: Time.current,
                            finished_at: Time.current, status: 'completed',
                            accessions: %w[PRJDB19940], mail_status:)
    }

    issued.(submissions(:bioproject), 'restricted')
    issued.(submissions(:biosample),  'sent')

    visit admin_accession_issuance_run_path(run)

    within all('[data-test-mail-outcome]').first do
      assert_text 'not delivered (restricted)'
      assert_no_text(/sent \d/)
    end

    # And the one that did go out still says so — a column that hedged
    # every row would be no more use than one that claimed every row.
    assert_text(/sent \d{4}-/)
  end

  # The single-submission page makes the claim in a sentence rather than
  # a column, and a green "The submitter has been emailed" is the version
  # of it a curator acts on: nobody follows up on a submitter they have
  # been told is already informed.
  test 'the issuance page does not tell a curator the submitter was emailed when nobody was' do
    submission = submissions(:bioproject)

    issuance = submission.accession_issuances.create!(
      actor: 'admin:bob', started_at: Time.current, finished_at: Time.current,
      status: 'completed', accessions: %w[PRJDB19940], mail_status: 'restricted'
    )

    visit admin_submission_accession_path(submission, issuance)

    assert_text    'No notification left the building'
    assert_no_text 'The submitter has been emailed'

    # Not a failure, and not dressed as one: the environment is behaving
    # as configured and there is nothing for the curator to repair.
    assert_no_selector '.alert-warning', text: 'not emailed'
  end

  # No address is the other one, and it IS work: this submitter cannot be
  # reached at all, and somebody has to reach them.
  test 'a submitter with no address on file is named as unreachable' do
    submission = submissions(:bioproject)
    submission.user.update!(email: nil)

    issuance = submission.accession_issuances.create!(
      actor: 'admin:bob', started_at: Time.current, finished_at: Time.current,
      status: 'completed', accessions: %w[PRJDB19940], mail_status: 'no_address'
    )

    visit admin_submission_accession_path(submission, issuance)

    assert_selector '.alert-warning', text: 'no address on file'
    assert_text     'told another way'
  end

  # A row that did not say. Only `sent` earns the green box — the two
  # screens used to part company here, the run page reading "not sent"
  # off the same row this one called a success.
  test 'an issuance with no recorded outcome is not reported as emailed' do
    submission = submissions(:bioproject)

    issuance = submission.accession_issuances.create!(
      actor: 'admin:bob', started_at: Time.current, finished_at: Time.current,
      status: 'completed', accessions: %w[PRJDB19940],
      error_message: 'Net::OpenTimeout: execution expired'
    )

    visit admin_submission_accession_path(submission, issuance)

    assert_no_text 'The submitter has been emailed'
    assert_text    'not recorded'

    # And whatever it did know is still on the page. The branch this
    # replaces was the one that printed no error at all.
    assert_text 'Net::OpenTimeout'
  end

  # Read off what issuance recorded, not worked out again at render time:
  # the restriction is temporary, and re-deriving it would turn every past
  # run into a claim that it had mailed people the day it is lifted.
  test 'a run says what happened when it ran, not what would happen now' do
    run = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: Time.current,
                                       origin: 'All requests (1 submission)')

    run.issuances.create!(submission: submissions(:bioproject), actor: run.actor,
                          started_at: Time.current, finished_at: Time.current,
                          status: 'completed', accessions: %w[PRJDB19940],
                          mail_status: 'restricted')

    MailDomainAllowlistInterceptor.stub(:registered, nil) do
      visit admin_accession_issuance_run_path(run)

      assert_no_selector '[data-test-mail-restricted]'
      assert_text        'not delivered (restricted)'
    end
  end
end
