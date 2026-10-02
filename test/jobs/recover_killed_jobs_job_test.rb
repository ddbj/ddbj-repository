require 'test_helper'

class RecoverKilledJobsJobTest < ActiveSupport::TestCase
  # The test database has no queue tables, so the failed jobs are handed
  # over in place of the query; what the query asks is checked on its own.
  test 'runs again the jobs whose process went away under them' do
    failed  = Array.new(2) { Struct.new(:job_id, :retried) { def retry = self.retried = true }.new(it) }
    asked   = nil
    results = Object.new.tap {|o| o.define_singleton_method(:find_each) {|&block| failed.each(&block) } }
    recent  = Object.new.tap {|o| o.define_singleton_method(:where) {|*args| asked = args; results } }

    SolidQueue::FailedExecution.stub(:where, recent) do
      RecoverKilledJobsJob.perform_now
    end

    assert failed.all?(&:retried)
    assert_equal RecoverKilledJobsJob::GONE, asked.last
  end
end
