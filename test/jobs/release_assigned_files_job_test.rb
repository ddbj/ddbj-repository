require 'test_helper'

class ReleaseAssignedFilesJobTest < ActiveJob::TestCase
  setup do
    @alice = users(:alice)
  end

  test 'a file used in a submission leaves the list' do
    blob = uploaded('record.json', content_type: 'application/json')

    @alice.unassigned_files_attachments.create!(blob:)

    assert submission_requests(:st26).ddbj_record.attach(blob), 'the fixture takes the record'

    assert_difference -> { @alice.unassigned_files.count }, -1 do
      ReleaseAssignedFilesJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(blob.id), 'the bytes belong to whatever uses it'
  end

  # What the list is for: a file uploaded days before the metadata that will
  # use it.
  test 'a file nothing uses stays' do
    @alice.unassigned_files_attachments.create!(blob: uploaded('waiting.fastq'))

    assert_no_difference -> { @alice.unassigned_files.count } do
      ReleaseAssignedFilesJob.perform_now
    end
  end

  # A message's attachments are called `files` too, so a rule that went by the
  # name alone would read one as part of this list and leave the copy in it.
  test 'a file sent in a message leaves the list' do
    blob = uploaded('reads.fastq')

    @alice.unassigned_files_attachments.create!(blob:)
    message = submission_requests(:st26).messages.create!(user: @alice, author_role: 'submitter', body: 'reads attached')

    assert message.files.attach(blob), 'the message takes the file'

    assert_difference -> { @alice.unassigned_files.count }, -1 do
      ReleaseAssignedFilesJob.perform_now
    end
  end

  # Two accounts holding the same blob are both still waiting; neither has
  # used it.
  test "another account's list does not count as using it" do
    blob = uploaded('shared.fastq')

    @alice.unassigned_files_attachments.create!(blob:)
    users(:carol).unassigned_files_attachments.create!(blob:)

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      ReleaseAssignedFilesJob.perform_now
    end
  end

  # Releasing is not purging: the purge that follows it half an hour later
  # decides what happens to the bytes, and a blob a submission holds stays.
  test 'releasing does not queue a purge' do
    blob = uploaded('record.json', content_type: 'application/json')

    @alice.unassigned_files_attachments.create!(blob:)
    submission_requests(:st26).ddbj_record.attach(blob)

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      ReleaseAssignedFilesJob.perform_now
    end
  end

  private

  def uploaded(filename, content_type: 'text/plain')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type:)
  end
end
