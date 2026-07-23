require 'test_helper'

class DistributionNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # projects(:primary): a bioproject submission owned by :alice.
  setup do
    @project = projects(:primary)
    @project.update!(status: :private, hold_date: Date.current + 10, distribution_notified_at: nil)
  end

  def bp_project(source_id:, accession:, user:, status: :private, hold_date: Date.current + 10)
    submission = Submission.create!(db: :bioproject, source_id:, user:)

    Project.create!(submission:, project_type: :primary, status:, accession:, hold_date:)
  end

  test 'notifies the submitter and marks the project, once' do
    result = nil

    assert_enqueued_emails 1 do
      result = DistributionNotifier.call
    end

    assert_not_nil @project.reload.distribution_notified_at
    assert_equal 1, result.notified_project_count
    assert_equal 1, result.notified_user_count

    # A second run does not re-notify an already-notified project.
    assert_no_enqueued_emails do
      DistributionNotifier.call
    end
  end

  test 'groups a submitter\'s projects into a single mail' do
    bp_project(source_id: 'PSUB-a', accession: 'PRJDB900001', user: @project.submission.user)

    # @project + the new one share the same user → one mail.
    assert_enqueued_emails 1 do
      DistributionNotifier.call
    end
  end

  test 'sends one mail per submitter' do
    bp_project(source_id: 'PSUB-b', accession: 'PRJDB900002', user: users(:bob))

    assert_enqueued_emails 2 do
      DistributionNotifier.call
    end
  end

  test 'ignores projects outside the notice window' do
    @project.update!(hold_date: Date.current + 30)

    assert_no_enqueued_emails do
      DistributionNotifier.call
    end
    assert_nil @project.reload.distribution_notified_at
  end

  test 'ignores non-embargoed projects' do
    @project.update!(status: :public)

    assert_no_enqueued_emails do
      DistributionNotifier.call
    end
  end

  test 'ignores projects with no hold_date' do
    @project.update!(hold_date: nil)

    assert_no_enqueued_emails do
      DistributionNotifier.call
    end
  end
end
