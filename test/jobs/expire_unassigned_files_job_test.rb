require 'test_helper'

class ExpireUnassignedFilesJobTest < ActiveJob::TestCase
  # Stands in for the relation the job sweeps, so one row can refuse to go.
  Sweep = Struct.new(:rows) do
    def where(*) = self

    def find_each(&) = rows.each(&)
  end

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

  # Expiry is about the list, not about the file: the attachment goes either
  # way, but a submission that was assigned the file keeps the bytes.
  test 'the bytes stay when a submission holds them' do
    assigned = attach('record.json', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day, content_type: 'application/json')

    assert submission_requests(:st26).ddbj_record.attach(assigned.blob)

    ExpireUnassignedFilesJob.perform_now

    assert_not ActiveStorage::Attachment.exists?(assigned.id), 'it leaves the list like any other'

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert ActiveStorage::Blob.exists?(assigned.blob_id), 'the submission holds it'
  end

  # A message's attachments are called `files` too, and everything else an
  # account may hold goes by another name. A rule that went by age alone would
  # take them all.
  test "another kind of attachment of the same age is not the list's" do
    message = submission_requests(:st26).messages.create!(user: @alice, author_role: 'submitter', body: 'reads attached')
    blob    = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename: 'reads.fastq', content_type: 'text/plain')

    assert message.files.attach(blob)

    message.files_attachments.sole.update_column :created_at, (ExpireUnassignedFilesJob::KEEP_FOR + 1.day).ago

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      ExpireUnassignedFilesJob.perform_now
    end
  end

  # Not even queued: what happens to the bytes is the purge's to decide, and a
  # blob a submission holds is one it decides to keep.
  test 'letting go of a file does not queue a purge' do
    attach('reads.fastq', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day)

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      ExpireUnassignedFilesJob.perform_now
    end
  end

  # The number itself, so that changing it is a decision rather than a typo
  # that the fixtures move along with.
  test 'a file may wait a week' do
    assert_equal 7.days, ExpireUnassignedFilesJob::KEEP_FOR
  end

  # One row that cannot be let go of would otherwise stop the sweep, and
  # `find_each` walks ids upward — so everything after it waits for ever.
  test 'a row that cannot be let go of does not stop the rest' do
    rest    = attach('reads.fastq', since: ExpireUnassignedFilesJob::KEEP_FOR + 1.day)
    failing = Object.new

    failing.define_singleton_method(:id) { 0 }
    failing.define_singleton_method(:destroy!) { raise ActiveRecord::RecordNotDestroyed }

    User.stub :unassigned_file_attachments, Sweep.new([failing, rest]) do
      ExpireUnassignedFilesJob.perform_now
    end

    assert_not ActiveStorage::Attachment.exists?(rest.id), 'the sweep went on'
  end

  private

  def attach(filename, since:, content_type: 'text/plain')
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type:)

    @alice.unassigned_files_attachments.create!(blob:, created_at: since.ago).tap do
      blob.update_column :created_at, since.ago
    end
  end
end
