# Makes a Blob of a finished multipart upload, once its contents are known.
#
# A Blob's checksum is the MD5 of the whole object, and the store does not
# have one for a multipart upload — its ETag is an MD5 of the parts' MD5s. So
# the object is read through and the Blob is created only when that is done.
# Until then there is no Blob, which is how MultipartUpload#state says
# "verifying".
#
# Reading the object rather than trusting the client: the checksum is what
# every later read of the file is checked against, so it has to describe what
# the store holds, not what somebody said they sent.
class VerifyMultipartUploadJob < ApplicationJob
  # Completing twice enqueues this twice, and each reads the whole file.
  limits_concurrency to: 1, key: ->(key, *) { key }

  # A store that cannot be read right now is no reason to give up on a file of
  # tens of GB, and none to discard it. Retried with growing waits; if it still
  # fails the job is left failed, the object stays, and completing the upload
  # again queues another attempt.
  retry_on Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, Net::ReadTimeout, Net::OpenTimeout,
           wait: :polynomially_longer, attempts: 10

  # Nor is a database that could not take the result for a moment, after the
  # whole file has been read. The read is repeated, which is the price of
  # keeping no half-finished state between runs.
  retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 5

  def perform(key, filename, content_type, byte_size, md5, user_id)
    return if ActiveStorage::Blob.exists?(key:)

    service = ActiveStorage::Blob.service
    client  = MultipartUpload.client
    bucket  = MultipartUpload.bucket

    stored = begin
      client.head_object(bucket:, key:).content_length
    rescue Aws::S3::Errors::NotFound
      # Rejected already, by an earlier run of this job.
      return
    end

    return reject(key) unless stored == byte_size

    digest = Digest::MD5.new

    # In ranges, as Active Storage reads every blob. One GET for the whole
    # object never gets as far as a byte in production: the storage proxy
    # (kamal-proxy, with response buffering on) writes the entire body to its
    # disk before it sends headers, and the client's read timeout runs out
    # long before a file of tens of GB is on that disk.
    service.download(key) { digest << it }

    return reject(key) if md5 && digest.hexdigest != md5.downcase

    # Into the uploader's files in the same commit, so the Blob is never
    # unattached for PurgeUnattachedUploadsJob to find. An account deleted in
    # the meantime leaves it unattached, which is what should collect it.
    #
    # Marked identified and analyzed, and attached by creating the attachment
    # rather than through `attach`. Either of those would otherwise read the
    # object again: identifying replaces the declared content type with a guess
    # from its first bytes, and analyzing an image or a video downloads all of
    # it. And `attach` answers a failed save with nil, which would leave a file
    # verified and then collected two days later without a word.
    ActiveRecord::Base.transaction do
      blob = ActiveStorage::Blob.create!(
        key:,
        filename:,
        content_type:,
        byte_size:,
        checksum:     digest.base64digest,
        service_name: service.name,
        metadata:     {identified: true, analyzed: true}
      )

      User.find_by(id: user_id)&.files_attachments&.create!(blob:)
    end
  rescue ActiveRecord::RecordNotUnique
    # Completed twice, verified twice; the first Blob stands.
  end

  private

  # Not the size it was started with, or not the file it was declared to be:
  # it cannot become a Blob, and nothing else refers to it.
  #
  # The object first, then any upload the store left behind after completing
  # it. In that order the abort cannot take data a live object still uses —
  # there is no live object by then — and without it the leftover upload would
  # answer as open, and the upload read as still `uploading`
  # (seaweedfs/seaweedfs#10663).
  def reject(key)
    client = MultipartUpload.client
    bucket = MultipartUpload.bucket

    client.delete_object(bucket:, key:)

    client.list_multipart_uploads(bucket:, prefix: key).uploads.select { it.key == key }.each do |upload|
      client.abort_multipart_upload(bucket:, key:, upload_id: upload.upload_id)
    end
  end
end
