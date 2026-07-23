require 'test_helper'

class Admin::DistributionNoticesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    sign_in_as users(:bob) # admin

    @project = projects(:primary) # bioproject submission owned by :alice
    @project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.current + 5, distribution_notified_at: nil)
  end

  test 'index lists submitters who are due for a release notice' do
    get admin_distribution_notices_path

    assert_response :ok
    assert_match @project.submission.user.uid, response.body
    assert_match 'PRJDB000001',                response.body
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

  test 'template edit + update persists a customised body' do
    get edit_admin_distribution_notice_template_path
    assert_response :ok

    patch admin_distribution_notice_template_path,
          params: {distribution_notifier_template: {subject: 'Custom subject', body: "Hi\n\n%{accessions}\n\nBye"}}

    assert_redirected_to edit_admin_distribution_notice_template_path
    assert_equal 'Custom subject', DistributionNotifierTemplate.instance.subject
  end

  test 'a template body without the placeholder is rejected' do
    patch admin_distribution_notice_template_path,
          params: {distribution_notifier_template: {subject: 'x', body: 'no placeholder'}}

    assert_response :unprocessable_content
  end
end
