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
        VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil)
      end
    end

    assert MultipartUpload.client.head_object(bucket: MultipartUpload.bucket, key: @key)
    assert_nil ActiveStorage::Blob.find_by(key: @key)
  end

  # Completing twice queues this twice; the second finds the work done.
  test 'a second run after the Blob exists does nothing' do
    VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil)

    assert_no_difference('ActiveStorage::Blob.count') do
      VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil)
    end
  end

  # Rejected by an earlier run: the object is gone, and that is not a failure.
  test 'a run after the object was rejected ends quietly' do
    MultipartUpload.client.delete_object(bucket: MultipartUpload.bucket, key: @key)

    assert_nothing_raised { VerifyMultipartUploadJob.perform_now(@key, 'reads.fastq', 'text/plain', 5, nil) }
    assert_nil ActiveStorage::Blob.find_by(key: @key)
  end
end
