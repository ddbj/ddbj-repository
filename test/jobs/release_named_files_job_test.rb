require 'test_helper'

class ReleaseNamedFilesJobTest < ActiveJob::TestCase
  setup do
    @alice = users(:alice)
  end

  test 'a file named in a submission leaves the area' do
    blob = uploaded('record.json', content_type: 'application/json')

    @alice.files_attachments.create!(blob:)

    assert submission_requests(:st26).ddbj_record.attach(blob), 'the fixture takes the record'

    assert_difference -> { @alice.files.count }, -1 do
      ReleaseNamedFilesJob.perform_now
    end

    assert ActiveStorage::Blob.exists?(blob.id), 'the bytes belong to whatever named it'
  end

  # What the area is for: a file uploaded days before the metadata that will
  # name it.
  test 'a file nothing has named stays' do
    @alice.files_attachments.create!(blob: uploaded('waiting.fastq'))

    assert_no_difference -> { @alice.files.count } do
      ReleaseNamedFilesJob.perform_now
    end
  end

  # A message's attachments are called `files` too, so a rule that went by the
  # name alone would read one as part of the area and leave the copy there.
  test 'a file sent in a message leaves the area' do
    blob = uploaded('reads.fastq')

    @alice.files_attachments.create!(blob:)
    message = submission_requests(:st26).messages.create!(user: @alice, author_role: 'submitter', body: 'reads attached')

    assert message.files.attach(blob), 'the message takes the file'

    assert_difference -> { @alice.files.count }, -1 do
      ReleaseNamedFilesJob.perform_now
    end
  end

  # Two accounts holding the same blob are both still waiting; neither has
  # named it.
  test "another account's area does not count as having named it" do
    blob = uploaded('shared.fastq')

    @alice.files_attachments.create!(blob:)
    users(:carol).files_attachments.create!(blob:)

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      ReleaseNamedFilesJob.perform_now
    end
  end

  # Releasing is not purging: the purge that follows it half an hour later
  # decides what happens to the bytes, and a blob a submission holds stays.
  test 'releasing does not queue a purge' do
    blob = uploaded('record.json', content_type: 'application/json')

    @alice.files_attachments.create!(blob:)
    submission_requests(:st26).ddbj_record.attach(blob)

    assert_no_enqueued_jobs only: ActiveStorage::PurgeJob do
      ReleaseNamedFilesJob.perform_now
    end
  end

  private

  def uploaded(filename, content_type: 'text/plain')
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type:)
  end
end
