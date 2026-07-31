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

  # A submitter with no address must stay a candidate: marking them
  # notified would drop them off the list without a mail ever going out.
  test 'skips submitters with no known address and leaves them pending' do
    @project.submission.user.update!(email: nil)

    result = nil

    assert_no_enqueued_emails do
      result = DistributionNotifier.call
    end

    assert_nil   @project.reload.distribution_notified_at
    assert_equal 0, result.notified_user_count
    assert_equal 1, result.skipped_user_count
  end

  test 'a skipped submitter does not hold back the others' do
    bp_project(source_id: 'PSUB-c', accession: 'PRJDB900003', user: users(:bob))
    @project.submission.user.update!(email: nil)

    result = nil

    assert_enqueued_emails 1 do
      result = DistributionNotifier.call
    end

    assert_equal 1, result.notified_user_count
    assert_equal 1, result.skipped_user_count
  end

  test 'ignores projects with no hold_date' do
    @project.update!(hold_date: nil)

    assert_no_enqueued_emails do
      DistributionNotifier.call
    end
  end

  # --- the send log --------------------------------------------------------

  test 'a delivered notice records what was sent and on whose say-so' do
    DistributionNotifier.call

    notice = DistributionNotice.sole

    assert_equal @project.submission.user, notice.user
    assert notice.delivered_result?
    assert notice.scheduled_trigger?
    assert_nil notice.actor
    assert_equal [@project.accession], notice.accessions
  end

  test 'a manual send names the curator who pressed it' do
    DistributionNotifier.new.notify(DistributionNotifier.new.candidates.to_a, trigger: :manual, actor: 'admin:bob')

    notice = DistributionNotice.sole

    assert notice.manual_trigger?
    assert_equal 'Manual · bob', notice.trigger_label
  end

  # Without this the due list cannot explain why a row is still there.
  test 'a skip is recorded too, with its reason' do
    @project.submission.user.update!(email: nil)

    DistributionNotifier.call

    notice = DistributionNotice.sole

    assert notice.skipped_result?
    assert_equal DistributionNotice::NO_ADDRESS, notice.skip_reason
    assert_equal [@project.accession],           notice.accessions
  end

  # The strip reports the schedule, so a curator's manual send in between
  # must not be mistaken for the last automatic run.
  test 'the last scheduled run is the batch of rows sharing its timestamp' do
    bp_project(source_id: 'PSUB-d', accession: 'PRJDB900004', user: users(:bob))

    DistributionNotifier.call

    assert_equal 2, DistributionNotice.last_scheduled_run.count

    Project.update_all(distribution_notified_at: nil)
    DistributionNotifier.new.notify(DistributionNotifier.new.candidates.to_a, trigger: :manual, actor: 'admin:bob')

    assert_equal 2, DistributionNotice.last_scheduled_run.count, 'a manual send is not a run of the schedule'
  end

  test 'blocked_since reports when a submitter first could not be reached' do
    user = @project.submission.user
    user.update!(email: nil)

    # `notify` directly, not `call`: the candidate window is relative to
    # "now", so travelling would move the window out from under the
    # fixture's hold date and the past run would find nothing.
    travel_to 3.days.ago do
      DistributionNotifier.new.notify([@project])
    end

    DistributionNotifier.new.notify([@project])

    assert_in_delta 3.days.ago, DistributionNotice.blocked_since([user.id]).fetch(user.id), 5
  end
end
