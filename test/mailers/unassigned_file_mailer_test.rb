require 'test_helper'

class UnassignedFileMailerTest < ActionMailer::TestCase
  setup do
    @alice = users(:alice)
  end

  test 'says what is going, when, and what keeps it' do
    files = [attach('reads_1.fastq', uploaded: 5.days.ago), attach('reads_2.fastq', uploaded: 4.days.ago)]

    mail = UnassignedFileMailer.with(user: @alice, attachment_ids: files.map(&:id)).expiry_notice

    assert_equal [@alice.email], mail.to

    # The subject names the first one to go, which is what the reader has to
    # answer first.
    assert_equal "Uploaded files waiting to be used will be removed on #{expiry(files.first).iso8601}",
                 mail.subject

    [mail.text_part, mail.html_part].each do |part|
      body = part.body.to_s

      assert_match 'reads_1.fastq', body
      assert_match 'reads_2.fastq', body

      # Each file's own date, not just the earliest: they are days apart.
      assert_match expiry(files.first).iso8601,  body
      assert_match expiry(files.second).iso8601, body

      assert_match 'use', body, 'what keeps the file'
    end
  end

  test 'reads for one file as well as for several' do
    mail = UnassignedFileMailer.with(user: @alice, attachment_ids: [attach('reads.fastq', uploaded: 5.days.ago).id])
                               .expiry_notice

    assert_match '1 file', mail.text_part.body.to_s
    assert_match 'is still waiting', mail.text_part.body.to_s
  end

  # The mail is delivered later, and by then the file may have been assigned or
  # taken out — in which case there is nothing to say.
  test 'nothing is sent when the files are gone by the time it is delivered' do
    file = attach('reads.fastq', uploaded: 5.days.ago)

    file.destroy!

    mail = UnassignedFileMailer.with(user: @alice, attachment_ids: [file.id]).expiry_notice

    assert_nil mail.subject
  end

  test 'nothing is sent to an account with no address' do
    file = attach('reads.fastq', uploaded: 5.days.ago)

    mail = UnassignedFileMailer.with(user: users(:carol), attachment_ids: [file.id]).expiry_notice

    assert_nil mail.subject
  end

  private

  def expiry(attachment) = (attachment.created_at + ExpireUnassignedFilesJob::KEEP_FOR).to_date

  def attach(filename, uploaded:)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type: 'text/plain')

    @alice.unassigned_files_attachments.create!(blob:, created_at: uploaded)
  end
end
