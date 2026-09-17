require 'test_helper'

# What it removes is a blob nobody attached, and only once nobody could still
# be about to: a direct upload is followed at once by the request that
# attaches it, so two days separates "abandoned" from "on its way".
class PurgeUnattachedUploadsJobTest < ActiveJob::TestCase
  test 'an old blob nobody attached is purged' do
    abandoned = blob(created_at: 3.days.ago)

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert_not ActiveStorage::Blob.exists?(abandoned.id)
  end

  # Asked of what the job sets out to purge, not of what survives: purging an
  # attached blob fails on the attachment's foreign key, so "it is still
  # there" would hold even if the job went after every blob in the table.
  test 'a blob that is attached is left alone, however old' do
    attached = blob(created_at: 3.days.ago)

    submission_requests(:st26).ddbj_record.attach(attached)

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) { PurgeUnattachedUploadsJob.perform_now }
  end

  test 'a blob uploaded moments ago is left alone' do
    blob(created_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) { PurgeUnattachedUploadsJob.perform_now }
  end

  private

  def blob(created_at:)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('{}'), filename: 'x.json', content_type: 'application/json').tap {
      it.update_column(:created_at, created_at)
    }
  end
end
