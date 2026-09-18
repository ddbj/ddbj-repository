require 'test_helper'

# Where an uploaded file waits to be named in a submission.
class FilesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"
  end

  test "an account's files are its own" do
    reads = add_file(@alice, 'reads.fastq', 'ACGT')
    add_file(users(:carol), 'theirs.fastq', 'TTTT')

    get files_path

    assert_conform_schema 200

    files = response.parsed_body

    assert_equal ['reads.fastq'],                files.pluck('filename')
    assert_equal Digest::MD5.hexdigest('ACGT'),  files.sole['md5']
    assert_equal reads.blob.signed_id,           files.sole['signed_blob_id']
    assert_equal '1',                            response.headers['Total-Pages']
  end

  test 'newest first, a page at a time' do
    # Created oldest first, so the order of ids disagrees with the order asked
    # for.
    files = 21.times.map {|i|
      add_file_record(@alice, "reads_#{i}.fastq", created_at: (21 - i).minutes.ago)
    }.reverse

    get files_path

    assert_conform_schema 200
    assert_equal files.take(20).map { it.blob.filename.to_s }, response.parsed_body.pluck('filename')
    assert_equal '2', response.headers['Total-Pages']

    get files_path, params: {page: 2}

    assert_conform_schema 200
    assert_equal [files.last.blob.filename.to_s], response.parsed_body.pluck('filename')
  end

  # Reading is not refused under a proxy: a curator helping somebody sees what
  # they have uploaded.
  test 'a curator acting for somebody sees their files' do
    add_file(@alice, 'reads.fastq', 'ACGT')

    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    get files_path

    assert_conform_schema 200
    assert_equal ['reads.fastq'], response.parsed_body.pluck('filename')
  end

  # Taken out of the list, not destroyed: a submission that names the same
  # file keeps it. What nothing refers to any more is collected with the
  # rest of what nobody attached.
  test 'removing a file detaches it, and its bytes go once nothing refers to it' do
    reads = add_file(@alice, 'reads.fastq', 'ACGT')
    blob  = reads.blob

    # Not even queued: a purge that fails because something else still holds
    # the blob is a failed job, and one that does not is a file gone that a
    # submission named.
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) { delete file_path(reads) }

    assert_response :no_content

    get files_path

    assert_empty response.parsed_body
    assert ActiveStorage::Blob.exists?(blob.id), 'detaching does not take the bytes'

    blob.update_column(:created_at, 3.days.ago)

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test 'a file that is still named somewhere else stays when it is taken out of the list' do
    reads = add_file(@alice, 'reads.fastq', 'ACGT')

    # Anything else holding the same blob will do; another account's data
    # files are one that is certain to save.
    assert users(:carol).files.attach(reads.blob)
    assert_equal 2, reads.blob.attachments.count

    delete file_path(reads)
    reads.blob.update_column(:created_at, 3.days.ago)

    perform_enqueued_jobs { PurgeUnattachedUploadsJob.perform_now }

    assert ActiveStorage::Blob.exists?(reads.blob.id)
  end

  test "somebody else's file cannot be removed" do
    theirs = add_file(users(:carol), 'theirs.fastq', 'TTTT')

    with_exceptions_app { delete file_path(theirs) }

    assert_conform_schema 404
  end

  # A curator acting for somebody can upload for them, but not discard what
  # they uploaded.
  test 'removing is refused while acting as another account' do
    reads = add_file(@alice, 'reads.fastq', 'ACGT')

    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    with_exceptions_app { delete file_path(reads) }

    assert_conform_schema 403
  end

  private

  # Rows only, for where the bytes do not matter and twenty uploads would.
  def add_file_record(user, filename, created_at:)
    blob = ActiveStorage::Blob.create!(
      key:          ActiveStorage::Blob.generate_unique_secure_token,
      filename:,
      content_type: 'text/plain',
      byte_size:    4,
      checksum:     Digest::MD5.base64digest('ACGT'),
      service_name: ActiveStorage::Blob.service.name,
      metadata:     {identified: true, analyzed: true}
    )

    user.files_attachments.create!(blob:, created_at:)
  end

  def add_file(user, filename, body)
    user.files.attach(io: StringIO.new(body), filename:, content_type: 'text/plain')
    user.files_attachments.order(:id).last
  end
end
