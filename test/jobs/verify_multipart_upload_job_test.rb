require 'test_helper'

class VerifyMultipartUploadJobTest < ActiveJob::TestCase
  setup do
    @key = ActiveStorage::Blob.generate_unique_secure_token

    MultipartUpload.client.put_object(bucket: MultipartUpload.bucket, key: @key, body: 'reads')
  end

  teardown do
    MultipartUpload.client.delete_object(bucket: MultipartUpload.bucket, key: @key)
  end

  # A file of tens of GB is not given up on, or thrown away, because the store
  # could not be read for a moment.
  test 'a store that cannot be read right now is tried again, and the object kept' do
    ActiveStorage::Blob.service.stub(:download, ->(*) { raise Seahorse::Client::NetworkingError, SocketError.new('down') }) do
      assert_enqueued_with(job: VerifyMultipartUploadJob) do
        VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, users(:alice).id)
      end
    end

    assert MultipartUpload.client.head_object(bucket: MultipartUpload.bucket, key: @key)
    assert_nil ActiveStorage::Blob.find_by(key: @key)
  end

  # Completing twice queues this twice; the second finds the work done.
  test 'a second run after the Blob exists does nothing' do
    VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, users(:alice).id)

    assert_no_difference('ActiveStorage::Blob.count') do
      VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, users(:alice).id)
    end
  end

  # Attached as it is created, so it is never a blob nobody attached — which is
  # what PurgeUnattachedUploadsJob removes after two days.
  test 'a verified file goes straight into the uploader\'s data files' do
    VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, users(:alice).id)

    assert_equal [@key], users(:alice).data_files.blobs.pluck(:key)
  end

  # The type is the uploader's word. Guessing it from the first bytes — which
  # attaching a Blob not yet identified does — would read the object again and
  # replace what was declared: gzipped reads declared as text come back as
  # application/gzip.
  test 'the declared content type stands' do
    gzipped = ActiveSupport::Gzip.compress('ACGT')

    MultipartUpload.client.put_object(bucket: MultipartUpload.bucket, key: @key, body: gzipped)

    assert_no_enqueued_jobs only: ActiveStorage::AnalyzeJob do
      VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', gzipped.bytesize, nil, users(:alice).id)
    end

    assert_equal 'text/plain', ActiveStorage::Blob.find_by!(key: @key).content_type
  end

  # Nobody to hold it, so it is what PurgeUnattachedUploadsJob is for.
  test 'the file of an account deleted meanwhile is left unattached' do
    VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, User.maximum(:id) + 1)

    assert_includes ActiveStorage::Blob.unattached.pluck(:key), @key
  end

  # Rejected by an earlier run: the object is gone, and that is not a failure.
  test 'a run after the object was rejected ends quietly' do
    MultipartUpload.client.delete_object(bucket: MultipartUpload.bucket, key: @key)

    assert_nothing_raised { VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil, users(:alice).id) }
    assert_nil ActiveStorage::Blob.find_by(key: @key)
  end
end
