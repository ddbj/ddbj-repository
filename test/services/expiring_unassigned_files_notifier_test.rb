require 'test_helper'

class ExpiringUnassignedFilesNotifierTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @alice = users(:alice)
  end

  # Two days before the end, so there is a working day to answer it in.
  test 'tells the owner what is about to go' do
    due = attach(@alice, 'reads.fastq', uploaded: 5.days.ago)

    assert_emails 1 do
      perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }
    end

    mail = ActionMailer::Base.deliveries.last

    assert_equal [@alice.email], mail.to
    assert_match 'reads.fastq', mail.body.encoded
    assert_match (due.created_at + ExpireUnassignedFilesJob::KEEP_FOR).to_date.iso8601, mail.body.encoded
  end

  # Past its day, this has nothing useful to say — and saying it would name a
  # date in the past. The file is the expiry job's now.
  test 'a file already past its day is not announced' do
    attach(@alice, 'reads.fastq', uploaded: (ExpireUnassignedFilesJob::KEEP_FOR + 1.day).ago)

    assert_no_emails do
      perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }
    end
  end

  test 'a file with days left is not mentioned yet' do
    attach(@alice, 'reads.fastq', uploaded: 1.day.ago)

    assert_no_emails do
      perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }
    end
  end

  # An account uploads a run's files together, and a run is what its owner
  # acts on.
  test 'one mail an account, however many files' do
    3.times {|i| attach(@alice, "reads_#{i}.fastq", uploaded: 5.days.ago) }
    attach(users(:dave), 'theirs.fastq', uploaded: 5.days.ago)

    result = nil

    assert_emails 2 do
      perform_enqueued_jobs { result = ExpiringUnassignedFilesNotifier.call }
    end

    assert_equal 4, result.notified_file_count
    assert_equal 2, result.notified_user_count
  end

  # The window catches a file the day after a run that did not happen; the
  # notice rows are what stop that from saying the same thing twice.
  test 'nobody is told twice' do
    attach(@alice, 'reads.fastq', uploaded: 5.days.ago)

    perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }

    assert_no_emails do
      perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }
    end
  end

  # Nothing can be sent, so the row says so. Keeping the file instead would
  # only mean holding it for ever, with no record of why.
  test 'an account with no known address is recorded as unmailable' do
    attach(users(:carol), 'reads.fastq', uploaded: 5.days.ago)

    result = nil

    assert_no_emails do
      perform_enqueued_jobs { result = ExpiringUnassignedFilesNotifier.call }
    end

    assert_equal 1, result.skipped_user_count

    notice = UnassignedFileNotice.sole

    assert_predicate notice, :skipped?
    assert_equal UnassignedFileNotice::NO_ADDRESS, notice.skip_reason
  end

  # The release job runs at 0:15 and this at 8:00, so a file assigned in
  # between — or any file at all, if that job failed — would be announced as
  # going. What it would cost is the owner uploading tens of GB again.
  test 'a file a submission holds is not announced, release job or not' do
    assigned = attach(@alice, 'record.json', uploaded: 5.days.ago, content_type: 'application/json')

    assert submission_requests(:st26).ddbj_record.attach(assigned.blob)

    assert_no_emails do
      perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }
    end

    assert_empty UnassignedFileNotice.all
  end

  # Gone with the file: once it has left the list there is nothing left to
  # warn about, and a row pointing at a destroyed attachment would be one more
  # thing to tidy.
  test 'the notice goes when the file does' do
    attach(@alice, 'reads.fastq', uploaded: 5.days.ago)

    perform_enqueued_jobs { ExpiringUnassignedFilesNotifier.call }

    assert_equal 1, UnassignedFileNotice.count

    @alice.unassigned_files_attachments.sole.destroy!

    assert_empty UnassignedFileNotice.all
  end

  private

  def attach(user, filename, uploaded:, content_type: 'text/plain')
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename:, content_type:)

    user.unassigned_files_attachments.create!(blob:, created_at: uploaded).tap do
      blob.update_column :created_at, uploaded
    end
  end
end
