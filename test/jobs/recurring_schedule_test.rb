require 'test_helper'
require 'fugit'

# Every recurring entry has to name a job that exists and a schedule that
# parses. Both failures are silent: the task simply never runs, and
# nothing on any screen says so — the only symptom is whatever the job
# was supposed to do not happening.
class RecurringScheduleTest < ActiveSupport::TestCase
  YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true).fetch('production').each do |key, task|
    test "recurring task #{key} names a job that exists and a schedule that parses" do
      job = task.fetch('class').safe_constantize

      assert_not_nil job, "#{task['class']} does not exist"
      assert_operator job, :<, ActiveJob::Base

      assert_not_nil Fugit.parse(task.fetch('schedule')), "cannot parse #{task['schedule'].inspect}"
    end
  end
end

class ClearFinishedJobsJobTest < ActiveSupport::TestCase
  # The deletion itself belongs to SolidQueue and cannot be exercised
  # here — the test environment queues through ActiveJob's test adapter
  # and has no queue database. What is ours is the wiring, and the way
  # it breaks is a gem upgrade moving the method out from under a job
  # that runs once a day where nobody is watching.
  test 'the method the job leans on is still there' do
    assert_respond_to SolidQueue::Job, :clear_finished_in_batches
  end

  # Deleting rows that finished minutes ago would take the queue browser
  # with it — "what ran today" is the question it exists to answer.
  test 'the retention window is a day, not zero' do
    assert_operator SolidQueue.clear_finished_jobs_after, :>=, 1.day
  end
end
