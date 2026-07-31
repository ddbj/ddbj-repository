require 'test_helper'

# The endpoints' own rules: what a manual send is scoped to, and what a
# test send refuses. What a curator reads and presses is
# test/system/distribution_notices_test.rb; who is due and what a run
# records is test/services/distribution_notifier_test.rb.
class Admin::DistributionNoticesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    sign_in_as users(:bob) # admin

    @project = projects(:primary) # bioproject submission owned by :alice
    @project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.current + 5, distribution_notified_at: nil)
  end

  # `user_id` narrows the batch to one submitter — the per-card button on
  # the due list, which must not quietly send everybody else's too.
  test 'Send for one submitter only notifies that submitter' do
    other = Submission.create!(db: :bioproject, source_id: 'PSUB-other', user: users(:carol))
    other_project = Project.create!(submission: other, project_type: :primary, status: :private, accession: 'PRJDB900001', hold_date: Date.current + 5)

    assert_enqueued_emails 1 do
      post admin_distribution_notices_path, params: {user_id: @project.submission.user_id}
    end

    assert_not_nil @project.reload.distribution_notified_at
    assert_nil     other_project.reload.distribution_notified_at
  end

  # --- what a test send refuses --------------------------------------------

  test 'a test send refuses when there is nothing real to render' do
    @project.update!(hold_date: nil)

    assert_no_enqueued_emails do
      patch admin_distribution_notice_template_path,
            params: {commit: 'test', distribution_notifier_template: default_template_params}
    end

    assert_match(/Nothing is due/, flash[:alert])
  end

  test 'a test send refuses when the curator has no address of their own' do
    users(:bob).update!(email: nil)

    assert_no_enqueued_emails do
      patch admin_distribution_notice_template_path,
            params: {commit: 'test', distribution_notifier_template: default_template_params}
    end

    assert_match(/no address on file/, flash[:alert])
  end

  # The whole point of a test send: it shows the edit, not the text the
  # edit replaces — and it publishes nothing.
  test 'a test send renders the unsaved edit and does not publish it' do
    perform_enqueued_jobs do
      patch admin_distribution_notice_template_path,
            params: {commit: 'test',
                     distribution_notifier_template: {subject: 'Draft subject', body: "Draft body\n\n%{accessions}"}}
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal 'Draft subject',            mail.subject
    assert_equal [users(:bob).email],        mail.to
    assert_not_equal 'Draft subject', DistributionNotifierTemplate.instance.subject, 'a test must not save'
    assert_equal 0, DistributionNotice.count, 'a test leaves no send-log row'
  end

  test 'the screen requires admin auth' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_distribution_notices_path
    end

    assert_response :forbidden
  end

  private

  def default_template_params
    {subject: DistributionNotifierTemplate::DEFAULT_SUBJECT, body: DistributionNotifierTemplate::DEFAULT_BODY}
  end
end
