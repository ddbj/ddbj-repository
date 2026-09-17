require 'test_helper'

# Where an uploaded data file waits to be named in a submission.
class DataFilesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"
  end

  test "an account's data files are its own" do
    reads = attach_data_file(@alice, 'reads.fastq', 'ACGT')
    attach_data_file(users(:carol), 'theirs.fastq', 'TTTT')

    get data_files_path

    assert_conform_schema 200

    files = response.parsed_body

    assert_equal ['reads.fastq'],                files.pluck('filename')
    assert_equal Digest::MD5.hexdigest('ACGT'),  files.sole['md5']
    assert_equal reads.blob.signed_id,           files.sole['signed_blob_id']
    assert_equal '1',                            response.headers['Total-Pages']
  end

  # Taken out of the list, not destroyed: a submission that names the same
  # file keeps it. What nothing refers to any more is collected with the
  # rest of what nobody attached.
  test 'removing a data file detaches it, and its bytes go once nothing refers to it' do
    reads = attach_data_file(@alice, 'reads.fastq', 'ACGT')
    blob  = reads.blob

    # Not even queued: a purge that fails because something else still holds
    # the blob is a failed job, and one that does not is a file gone that a
    # submission named.
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) { delete data_file_path(reads) }

    assert_response :no_content

    get data_files_path

    assert_empty response.parsed_body
    assert ActiveStorage::Blob.exists?(blob.id), 'detaching does not take the bytes'

    blob.update_column(:created_at, 3.days.ago)

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test 'a file that is still named somewhere else stays when it is taken out of the list' do
    reads = attach_data_file(@alice, 'reads.fastq', 'ACGT')

    # Anything else holding the same blob will do; another account's data
    # files are one that is certain to save.
    assert users(:carol).data_files.attach(reads.blob)
    assert_equal 2, reads.blob.attachments.count

    delete data_file_path(reads)
    reads.blob.update_column(:created_at, 3.days.ago)

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert ActiveStorage::Blob.exists?(reads.blob.id)
  end

  test "somebody else's data file cannot be removed" do
    theirs = attach_data_file(users(:carol), 'theirs.fastq', 'TTTT')

    with_exceptions_app { delete data_file_path(theirs) }

    assert_conform_schema 404
  end

  # A curator acting for somebody can upload for them, but not discard what
  # they uploaded.
  test 'removing is refused while acting as another account' do
    reads = attach_data_file(@alice, 'reads.fastq', 'ACGT')

    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    with_exceptions_app { delete data_file_path(reads) }

    assert_conform_schema 403
  end

  private

  def attach_data_file(user, filename, body)
    user.data_files.attach(io: StringIO.new(body), filename:, content_type: 'text/plain')
    user.data_files_attachments.order(:id).last
  end
end
