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
#   holds no store credentials — carried in a token instead of a row;
# - turn the finished object into a Blob, whose checksum is the MD5 of the
#   whole file. A multipart ETag is not that, so it is computed afterwards, by
#   reading the object (VerifyMultipartUploadJob).
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

  # How long an upload can be carried on through this API, counted from when
  # it began and not extended by using it. The store does not expire an
  # unfinished upload by itself; after this its parts are only reachable by
  # whoever cleans the store up.
  RESUMABLE_FOR = 7.days

  # A signed URL is for sending one part, not for keeping.
  PART_URL_TTL = 1.hour

  # The name and type ride in the token, and the token rides in the path — a
  # long enough name makes a token no server will route. Bytes, not
  # characters, because that is what a path is measured in.
  MAX_FILENAME     = 255
  MAX_CONTENT_TYPE = 255

  MD5_HEX = /\A\h{32}\z/

  ATTRIBUTES = %i[user_id key upload_id filename content_type byte_size md5 started_at].freeze

  attr_reader(*ATTRIBUTES)

  def self.start!(user:, filename:, content_type:, byte_size:, md5: nil)
    key    = ActiveStorage::Blob.generate_unique_secure_token
    upload = client.create_multipart_upload(bucket:, key:, content_type:)

    new(user_id: user.id, key:, upload_id: upload.upload_id, filename:, content_type:, byte_size:, md5:, started_at: Time.current.to_i)
  end

  # Whose upload it is travels in the token, so the token alone is not enough:
  # somebody else's is refused as if it did not exist. So is one of a shape
  # this code does not know — a token from before a change to what it carries
  # is not a reason for a 500.
  def self.find(token, user:)
    attrs = encryptor.decrypt_and_verify(token, purpose: :multipart_upload) or raise NotFound
    attrs = attrs.symbolize_keys

    raise NotFound unless attrs.keys.sort == ATTRIBUTES.sort && attrs[:user_id] == user.id

    new(**attrs)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError, TypeError, NoMethodError
    raise NotFound
  end

  def self.max_byte_size = MAX_PARTS * MAX_PART

  def self.part_size_for(byte_size)
    [part_size_floor, round_up_to_mib((byte_size.to_f / MAX_PARTS).ceil)].max
  end

  def self.part_size_floor = PART_SIZE

  def self.round_up_to_mib(bytes) = (bytes.to_f / 1.megabyte).ceil * 1.megabyte

  def self.client = ActiveStorage::Blob.service.client.client

  def self.bucket = ActiveStorage::Blob.service.bucket.name

  # Encrypted as well as signed. The token goes in a URL path, and paths are
  # written down — in the request log, the proxy's, Nginx's, an error report —
  # where a filename and a checksum have no business being readable. URL-safe
  # for the same reason.
  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key('multipart_upload', ActiveSupport::MessageEncryptor.key_len),
      url_safe:   true,
      serializer: JSON
    )
  end

  def initialize(user_id:, key:, upload_id:, filename:, content_type:, byte_size:, md5:, started_at:)
    @user_id      = user_id
    @key          = key
    @upload_id    = upload_id
    @filename     = filename
    @content_type = content_type
    @byte_size    = byte_size
    @md5          = md5
    @started_at   = started_at
  end

  # The same expiry however often it is issued. Minted with a fresh
  # `expires_in` on every response, a client that kept asking kept its upload
  # alive for ever.
  def token
    @token ||= self.class.encryptor.encrypt_and_sign(
      ATTRIBUTES.to_h { [it, public_send(it)] },
      purpose:    :multipart_upload,
      expires_at: expires_at
    )
  end

  def expires_at = Time.zone.at(started_at) + RESUMABLE_FOR

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
  # answers a second request for a finished upload as done, and verifying a
  # file that already has its Blob does nothing.
  def complete!(etags)
    exclusively do
      client.complete_multipart_upload(
        bucket:,
        key:,
        upload_id:,
        multipart_upload: {parts: etags.sort_by(&:first).map {|number, etag| {part_number: number, etag:} }}
      )

      VerifyMultipartUploadJob.perform_later(key, filename, content_type, byte_size, md5, user_id)
    end
  end

  # Not once the object exists. Aborting the upload of a finished object
  # deletes the object's data when the store left the upload behind after
  # completing it — seaweedfs/seaweedfs#10663. Under the same lock as
  # `complete!`, so a completion cannot land between the check and the abort.
  def abort!
    exclusively do
      raise AlreadyComplete if object_exists?

      client.abort_multipart_upload(bucket:, key:, upload_id:)
    end
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

  # Everything a response says about where the upload is, asked of the store in
  # one place. Taken before rendering, so a store that does not answer fails the
  # action — where it can be answered as that — and not the template.
  Snapshot = Data.define(:state, :parts, :signed_blob_id)

  def snapshot
    state = self.state

    Snapshot.new(
      state:,
      parts:          state == :uploading ? parts : [],
      signed_blob_id: state == :ready ? blob.signed_id : nil
    )
  end

  private

  def client = self.class.client

  def bucket = self.class.bucket

  # One upload at a time, across processes, for as long as the block runs.
  # A transaction-scoped advisory lock: nothing to create, and nothing left
  # held if the process dies.
  def exclusively(&)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql(['SELECT pg_advisory_xact_lock(hashtext(?))', "multipart_upload:#{key}"])
      )

      yield
    end
  end

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
