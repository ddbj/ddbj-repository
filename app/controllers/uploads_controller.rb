# Resumable uploads of data files, straight to the object store in parts.
#
# The client starts one, asks for signed URLs for the parts it is about to
# send, PUTs them to the store itself, and completes it with the ETags the
# store gave back. If it stops, it asks what the store already has and sends
# the rest. When the upload is verified it is a Blob in the uploader's data
# files (DataFilesController), and named elsewhere by its signed id.
#
# The token names the upload. It is not a credential on its own: every
# request here is also authenticated, and a token of somebody else's is a 404.
class UploadsController < ApplicationController
  # The store could not be asked. Distinct from a refusal: nothing about the
  # request was wrong, and the same request may work in a minute.
  class StoreUnavailable < StandardError
    include PublicError
  end

  # Enough URLs for a client sending several parts at once to keep going for a
  # while, and few enough that one request cannot sign an entire upload.
  MAX_PART_URLS = 100

  # What the store says when completion is the client's mistake: a part it
  # does not have, parts out of order, a part other than the last under the
  # store's minimum, an upload already gone.
  CLIENT_COMPLETION_ERRORS = [
    Aws::S3::Errors::InvalidPart,
    Aws::S3::Errors::InvalidPartOrder,
    Aws::S3::Errors::EntityTooSmall,
    Aws::S3::Errors::NoSuchUpload
  ].freeze

  # An around action, not `rescue_from`. `rescue_from` also matches an
  # exception by its cause, and every refusal made while handling a store
  # error has that error as its cause — so a 422 for a part under the store's
  # minimum was taken over and answered as the store being down.
  around_action :answer_store_failures

  # Abandoning an upload discards what the account holder may have sent, and
  # that is theirs to do — as taking a finished file out of their data files is.
  before_action :refuse_proxy!, only: %i[destroy]

  before_action :load_upload, except: %i[create]

  def create
    attrs        = params.expect(upload: %i[filename content_type byte_size md5])
    filename     = attrs[:filename].to_s
    content_type = attrs[:content_type].presence || 'application/octet-stream'
    byte_size    = whole_number(attrs[:byte_size])
    md5          = attrs[:md5].presence

    refuse! "filename is required, of at most #{MultipartUpload::MAX_FILENAME} bytes." unless printable?(filename, MultipartUpload::MAX_FILENAME)
    refuse! "content_type must be at most #{MultipartUpload::MAX_CONTENT_TYPE} bytes." unless printable?(content_type, MultipartUpload::MAX_CONTENT_TYPE)

    unless byte_size&.between?(1, MultipartUpload.max_byte_size)
      refuse! "byte_size must be a whole number between 1 and #{MultipartUpload.max_byte_size}."
    end

    refuse! 'md5 must be 32 hexadecimal digits.' if md5 && !md5.to_s.match?(MultipartUpload::MD5_HEX)

    @upload   = MultipartUpload.start!(user: current_user, filename:, content_type:, byte_size:, md5:)
    @snapshot = @upload.snapshot

    render :show, status: :created
  end

  def show
    @snapshot = @upload.snapshot
  end

  def part_urls
    numbers = Array(params.expect(part_numbers: [])).map { whole_number(it) }

    refuse! 'part_numbers is required.' if numbers.empty?
    refuse! "At most #{MAX_PART_URLS} part URLs at a time." if numbers.size > MAX_PART_URLS

    unless numbers.all? { it&.between?(1, @upload.part_count) }
      refuse! "part_numbers must be whole numbers between 1 and #{@upload.part_count}."
    end

    @urls = @upload.part_urls(numbers.uniq)
  end

  # Every part, each exactly once. The store would complete an upload with a
  # part missing — it only requires them in order — and the object would be
  # the wrong file. A part named twice is refused rather than one copy chosen:
  # `parts` lists every copy the store holds, and a client that sent that list
  # back meant one of them.
  def complete
    parts   = params.expect(parts: [%i[part_number etag]])
    numbers = parts.map { whole_number(it[:part_number]) }

    unless numbers.sort == (1..@upload.part_count).to_a && parts.none? { it[:etag].blank? }
      refuse! "parts must name every part from 1 to #{@upload.part_count}, each exactly once, with its ETag."
    end

    @upload.complete!(numbers.zip(parts.map { it[:etag].to_s }))

    @snapshot = @upload.snapshot

    render :show, status: :accepted
  rescue *CLIENT_COMPLETION_ERRORS => e
    refuse! "The store refused to complete the upload: #{e.message}"
  end

  def destroy
    @upload.abort!

    head :no_content
  rescue MultipartUpload::AlreadyComplete
    refuse! 'This upload is already complete, and cannot be aborted.'
  end

  private

  def answer_store_failures
    yield
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError
    raise StoreUnavailable, 'The object store did not answer. Try again shortly.'
  end

  def load_upload
    @upload = MultipartUpload.find(params.expect(:token), user: current_user)
  rescue MultipartUpload::NotFound
    raise ActiveRecord::RecordNotFound, "Couldn't find Upload"
  end

  # A JSON integer, or a string of digits. Not a float truncated to one, and not
  # whatever `Integer()` makes of "0x10".
  def whole_number(value)
    case value
    when Integer        then value
    when /\A[0-9]{1,20}\z/ then value.to_i
    end
  end

  # Something a header or a path can carry.
  def printable?(value, max_bytes)
    value.present? && value.bytesize <= max_bytes && !value.match?(/[[:cntrl:]]/)
  end
end
