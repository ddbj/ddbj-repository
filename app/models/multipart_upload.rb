# One data file, uploaded straight to the object store in parts that can be
# sent again and picked up where they stopped.
#
# The store keeps the upload: which parts it has, whether it is still open,
# when it began. Nothing here copies that. A table of sessions was the first
# design, and it was a second account of state the store already holds, with
# nothing to decide which is right when they disagree. What this adds is only
# what the store cannot do:
#
# - say who may carry the upload on, and sign what they send, since a client
#   holds no store credentials — carried in a signed token instead of a row;
# - turn the finished object into a Blob, whose checksum is the MD5 of the
#   whole file. A multipart ETag is not that, so it is computed afterwards,
#   by reading the object (VerifyMultipartUploadJob).
#
# For data files. Everything else still goes through Active Storage's direct
# upload, which is one PUT and has no reason to be more.
class MultipartUpload
  class NotFound < StandardError; end

  class AlreadyComplete < StandardError; end

  # The store's own rules. Every part but the last must be at least 5 MiB, no
  # upload has more than 10,000 parts, and no part is over 5 GiB.
  STORE_MINIMUM_PART = 5.megabytes
  MAX_PARTS          = 10_000
  MAX_PART           = 5.gigabytes

  # Parts this size unless the file is too large to fit in MAX_PARTS of them.
  # Small enough that a part lost on a slow link costs little to send again;
  # large enough that a genome's worth of reads is not tens of thousands of
  # requests.
  PART_SIZE = 16.megabytes

  # How long an upload can be picked up again, counted from when it began —
  # the way the store counts it too.
  RESUMABLE_FOR = 7.days

  # A signed URL is for sending one part, not for keeping.
  PART_URL_TTL = 1.hour

  MD5_HEX = /\A\h{32}\z/

  attr_reader :user_id, :key, :upload_id, :filename, :content_type, :byte_size, :md5

  def self.start!(user:, filename:, content_type:, byte_size:, md5: nil)
    key    = ActiveStorage::Blob.generate_unique_secure_token
    upload = client.create_multipart_upload(bucket:, key:, content_type:)

    new(user_id: user.id, key:, upload_id: upload.upload_id, filename:, content_type:, byte_size:, md5:)
  end

  # Whose upload it is travels in the token, so the token alone is not enough:
  # somebody else's is refused as if it did not exist.
  def self.find(token, user:)
    attrs = verifier.verified(token, purpose: :multipart_upload) or raise NotFound

    raise NotFound unless attrs['user_id'] == user.id

    new(**attrs.symbolize_keys)
  end

  # Largest first: the size a file is allowed to be is set by the parts it can
  # be cut into.
  def self.max_byte_size = MAX_PARTS * MAX_PART

  def self.part_size_for(byte_size)
    [part_size_floor, (byte_size.to_f / MAX_PARTS).ceil.then { round_up_to_mib(it) }].max
  end

  def self.part_size_floor = PART_SIZE

  def self.round_up_to_mib(bytes) = (bytes.to_f / 1.megabyte).ceil * 1.megabyte

  def self.client = ActiveStorage::Blob.service.client.client

  def self.bucket = ActiveStorage::Blob.service.bucket.name

  # URL-safe, because the token goes in the path.
  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key('multipart_upload'),
      url_safe:   true,
      serializer: JSON
    )
  end

  def initialize(user_id:, key:, upload_id:, filename:, content_type:, byte_size:, md5: nil)
    @user_id      = user_id
    @key          = key
    @upload_id    = upload_id
    @filename     = filename
    @content_type = content_type
    @byte_size    = byte_size
    @md5          = md5
  end

  def token
    @token ||= self.class.verifier.generate(
      {user_id:, key:, upload_id:, filename:, content_type:, byte_size:, md5:},
      purpose:    :multipart_upload,
      expires_in: RESUMABLE_FOR
    )
  end

  def part_size = self.class.part_size_for(byte_size)

  def part_count = [(byte_size.to_f / part_size).ceil, 1].max

  # What the store has, part by part, and every copy of a part that was sent
  # more than once: the store lists each, and only the client — which knows
  # what it sent — can tell which to keep. See `complete!`.
  def parts
    client.list_parts(bucket:, key:, upload_id:).each_page.flat_map(&:parts)
  end

  def part_urls(numbers)
    presigner = Aws::S3::Presigner.new(client:)

    numbers.to_h {|number|
      [number, presigner.presigned_url(:upload_part, bucket:, key:, upload_id:, part_number: number, expires_in: PART_URL_TTL.to_i)]
    }
  end

  # The ETags are the client's, because only the client knows which of two
  # copies of a part it meant. Completing is safe to ask for twice: the store
  # answers a second request for a finished upload as done, so a client that
  # lost the first answer asks again.
  def complete!(etags)
    client.complete_multipart_upload(
      bucket:,
      key:,
      upload_id:,
      multipart_upload: {parts: etags.sort_by(&:first).map {|number, etag| {part_number: number, etag:} }}
    )

    VerifyMultipartUploadJob.perform_later(key:, filename:, content_type:, byte_size:, md5:)
  end

  # Not once the object exists. Aborting the upload of a finished object
  # deletes the object's data when the store left the upload behind after
  # completing it — seaweedfs/seaweedfs#10663.
  def abort!
    raise AlreadyComplete if object_exists?

    client.abort_multipart_upload(bucket:, key:, upload_id:)
  end

  # Read in this order because each answer settles the ones after it: a Blob
  # means verified; an object without one means verification has not finished;
  # an open upload means parts are still coming.
  def state
    return :ready     if blob
    return :verifying if object_exists?
    return :uploading if open?

    :rejected
  end

  def blob = ActiveStorage::Blob.find_by(key:)

  private

  def client = self.class.client

  def bucket = self.class.bucket

  def object_exists?
    client.head_object(bucket:, key:)

    true
  rescue Aws::S3::Errors::NotFound
    false
  end

  def open?
    client.list_parts(bucket:, key:, upload_id:, max_parts: 1)

    true
  rescue Aws::S3::Errors::NoSuchUpload
    false
  end
end
