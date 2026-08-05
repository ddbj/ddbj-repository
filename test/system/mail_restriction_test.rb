require 'application_system_test_case'

# Every deployed environment restricts outgoing mail to DDBJ while
# sending to real submitters is still switched off. The screens that send
# it cannot say so on their own — a suppressed delivery is not a failure,
# so an accession run reports "sent" whether or not anything left the
# building — which is why the environment says it instead.
class MailRestrictionSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  test 'the restriction is on every admin screen while it is in force' do
    MailDomainAllowlistInterceptor.stub(:domains, %w[ddbj.nig.ac.jp ursm.jp]) do
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
    MailDomainAllowlistInterceptor.stub(:domains, nil) do
      visit admin_root_path

      assert_no_selector '[data-test-mail-restricted]'
    end
  end
end
