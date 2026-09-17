# Makes a Blob of a finished multipart upload, once its contents are known.
#
# A Blob's checksum is the MD5 of the whole object, and the store does not
# have one for a multipart upload — its ETag is an MD5 of the parts' MD5s. So
# the object is read through, in chunks as it comes, and the Blob is created
# only when that is done. Until then there is no Blob, which is how
# MultipartUpload#state says "verifying".
#
# Reading the object rather than trusting the client: the checksum is what
# every later read of the file is checked against, so it has to describe what
# the store holds, not what somebody said they sent.
class VerifyMultipartUploadJob < ApplicationJob
  def perform(key:, filename:, content_type:, byte_size:, md5:)
    return if ActiveStorage::Blob.exists?(key:)

    client = MultipartUpload.client
    bucket = MultipartUpload.bucket

    # Not the size it was started with, or not the file it was declared to be:
    # the object goes. It cannot become a Blob, and nothing else refers to it.
    # A failure to read it is not one of these — that raises and is retried,
    # and the object stays, because an unreachable store is no reason to
    # throw away somebody's upload.
    stored = client.head_object(bucket:, key:).content_length

    return client.delete_object(bucket:, key:) unless stored == byte_size

    digest = Digest::MD5.new

    client.get_object(bucket:, key:) {|chunk| digest << chunk }

    return client.delete_object(bucket:, key:) if md5 && digest.hexdigest != md5.downcase

    ActiveStorage::Blob.create!(
      key:,
      filename:,
      content_type:,
      byte_size:,
      checksum:     digest.base64digest,
      service_name: ActiveStorage::Blob.service.name
    )
  rescue ActiveRecord::RecordNotUnique
    # Completed twice, verified twice; the first Blob stands.
  end
end
