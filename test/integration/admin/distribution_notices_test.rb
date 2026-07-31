require 'test_helper'

class Admin::DistributionNoticesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    sign_in_as users(:bob) # admin

    @project = projects(:primary) # bioproject submission owned by :alice
    @project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.current + 5, distribution_notified_at: nil)
  end

  # --- Due now -------------------------------------------------------------

  test 'index lists submitters who are due for a release notice' do
    @project.update!(title: 'Soil metagenome survey')

    get admin_distribution_notices_path

    assert_response :ok
    assert_match @project.submission.user.uid, response.body
    assert_match 'PRJDB000001',                response.body

    # The accession alone does not say what is about to become public.
    assert_match 'Soil metagenome survey', response.body
  end

  test 'Send all now mails the pending submitters and marks them notified' do
    assert_enqueued_emails 1 do
      post admin_distribution_notices_path
    end

    assert_redirected_to admin_distribution_notices_path
    assert_not_nil @project.reload.distribution_notified_at
  end

  test 'Send for one submitter only notifies that submitter' do
    other = Submission.create!(db: :bioproject, source_id: 'PSUB-other', user: users(:carol))
    other_project = Project.create!(submission: other, project_type: :primary, status: :private, accession: 'PRJDB900001', hold_date: Date.current + 5)

    assert_enqueued_emails 1 do
      post admin_distribution_notices_path, params: {user_id: @project.submission.user_id}
    end

    assert_not_nil @project.reload.distribution_notified_at
    assert_nil     other_project.reload.distribution_notified_at
  end

  # A blocked submitter used to be a disabled button inside their own card,
  # with nothing saying how long it had been that way.
  test 'submitters with no address are collected at the top with how long they have been stuck' do
    @project.submission.user.update!(email: nil)

    travel_to 4.days.ago do
      DistributionNotifier.new.notify([@project])
    end

    get admin_distribution_notices_path

    assert_response :ok
    assert_match 'BLOCKED',                     response.body
    assert_match 'no address on file',          response.body
    assert_match 4.days.ago.to_date.iso8601,    response.body
    assert_match admin_users_path(q: @project.submission.user.uid), response.body
  end

  # --- the automation strip ------------------------------------------------

  test 'the strip reports the result of the last scheduled run' do
    DistributionNotifier.call

    get admin_distribution_notices_path

    assert_response :ok
    assert_match 'Last run',      response.body
    assert_match '1 notice',      response.body
    assert_match '1 submitter',   response.body
    assert_match admin_mission_control_jobs_path, response.body
  end

  test 'a curator manual send is not reported as a run of the schedule' do
    post admin_distribution_notices_path

    get admin_distribution_notices_path

    assert_response :ok
    assert_match 'It has not run yet.', response.body
  end

  # --- Sent ----------------------------------------------------------------

  test 'the sent tab answers "was this submitter told?"' do
    DistributionNotifier.call

    get admin_distribution_notices_path(tab: 'sent')

    assert_response :ok
    assert_match @project.submission.user.uid, response.body
    assert_match 'PRJDB000001',                response.body
    assert_match 'Scheduled',                  response.body
    assert_match 'Delivered',                  response.body
  end

  test 'a manual send is recorded against the curator who sent it' do
    post admin_distribution_notices_path

    get admin_distribution_notices_path(tab: 'sent')

    assert_response :ok
    assert_match 'Manual · bob', response.body
  end

  # Without the skip in the history, the due list cannot explain itself.
  test 'a skip appears in the history with its reason' do
    @project.submission.user.update!(email: nil)

    DistributionNotifier.call

    get admin_distribution_notices_path(tab: 'sent')

    assert_response :ok
    assert_match 'Skipped',    response.body
    assert_match 'no address', response.body
  end

  test 'the sent tab searches by accession and by submitter' do
    DistributionNotifier.call

    get admin_distribution_notices_path(tab: 'sent', q: 'PRJDB000001')
    assert_match @project.submission.user.uid, response.body

    get admin_distribution_notices_path(tab: 'sent', q: @project.submission.user.uid)
    assert_match 'PRJDB000001', response.body

    get admin_distribution_notices_path(tab: 'sent', q: 'PRJDB999999')
    assert_match 'No notices match this search.', response.body
  end

  # --- Template ------------------------------------------------------------

  test 'the template tab edits the mail and previews it against a real candidate' do
    get admin_distribution_notices_path(tab: 'template')

    assert_response :ok
    assert_match 'Preview',                                      response.body
    assert_match @project.submission.user.email,                 response.body
    assert_match 'PRJDB000001',                                  response.body
    assert_match DistributionNotifierTemplate::DEFAULT_SUBJECT,  response.body
  end

  test 'update persists a customised body and comes back to the tab' do
    patch admin_distribution_notice_template_path,
          params: {distribution_notifier_template: {subject: 'Custom subject', body: "Hi\n\n%{accessions}\n\nBye"}}

    assert_redirected_to admin_distribution_notices_path(tab: 'template')
    assert_equal 'Custom subject', DistributionNotifierTemplate.instance.subject
  end

  test 'a template body without the placeholder is rejected on the same tab' do
    patch admin_distribution_notice_template_path,
          params: {distribution_notifier_template: {subject: 'x', body: 'no placeholder'}}

    assert_response :unprocessable_content
    assert_match 'must contain the', response.body
  end

  # Saving is publishing — the next run sends it to everybody — so a copy
  # addressed to yourself is the only way to look before that happens.
  test 'a test send goes to the curator and marks nothing as notified' do
    assert_enqueued_emails 1 do
      post test_delivery_admin_distribution_notices_path
    end

    assert_redirected_to admin_distribution_notices_path(tab: 'template')
    assert_nil @project.reload.distribution_notified_at, 'a test is not a notice'
    assert_equal 0, DistributionNotice.count, 'a test leaves no send-log row'
  end

  test 'a test send refuses when there is nothing real to render' do
    @project.update!(hold_date: nil)

    assert_no_enqueued_emails do
      post test_delivery_admin_distribution_notices_path
    end

    assert_match(/Nothing is due/, flash[:alert])
  end

  # --- authorisation -------------------------------------------------------

  test 'the screen requires admin auth' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_distribution_notices_path
    end

    assert_response :forbidden
  end
end
