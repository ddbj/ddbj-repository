require 'test_helper'

class ExpireUnassignedFilesJobTest < ActiveJob::TestCase
  setup do
    @alice = users(:alice)
  end

  # What the list is for — reads uploaded days before their metadata — is also
  # what says how long it may sit there.
  test 'a file nothing was ever assigned is let go of after a week' do
    waiting = attach('reads.fastq', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day)

    assert_difference -> { @alice.unassigned_files.count }, -1 do
      ExpireUnassignedFilesJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(waiting.blob_id), 'the bytes are the purge to decide on'
  end

  test 'a file still within the week stays' do
    attach('reads.fastq', since: ExpireUnassignedFilesJob::KEEP_FOR - 1.day)

    assert_no_difference -> { @alice.unassigned_files.count } do
      ExpireUnassignedFilesJob.perform_now
    end
  end

  # Half an hour later, and by then nothing holds the blob, so this is what
  # takes the bytes. The two jobs are one decision split in two places.
  test 'the purge that follows collects what expired' do
    expired = attach('reads.fastq', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day)
    blob    = expired.blob

    ExpireUnassignedFilesJob.perform_now

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  # Expiry is about the list, not about the file: a submission that was
  # assigned it keeps it, however long ago it was uploaded.
  test 'a file a submission was assigned is not touched here' do
    assigned = attach('record.json', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day, content_type: 'application/json')

    assert submission_requests(:st26).ddbj_record.attach(assigned.blob)

    ExpireUnassignedFilesJob.perform_now

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert ActiveStorage::Blob.exists?(assigned.blob_id), 'the submission holds it'
  end

  private

  def attach(filename, since:, content_type: 'text/plain')
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type:)

    @alice.unassigned_files_attachments.create!(blob:, created_at: since.ago).tap do
      blob.update_column :created_at, since.ago
    end
  end
end
