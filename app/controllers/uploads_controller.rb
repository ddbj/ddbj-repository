# Resumable uploads of data files, straight to the object store in parts.
#
# The client starts one, asks for signed URLs for the parts it is about to
# send, PUTs them to the store itself, and completes it with the ETags the
# store gave back. If it stops, it asks what the store already has and sends
# the rest. When the upload is verified it is a Blob, attached through its
# signed id like any other.
#
# The token names the upload. It is not a credential on its own: every
# request here is also authenticated, and a token of somebody else's is a 404.
class UploadsController < ApplicationController
  # Enough URLs for a client sending several parts at once to keep going for a
  # while, and few enough that one request cannot sign an entire upload.
  MAX_PART_URLS = 100

  before_action :load_upload, except: %i[create]

  def create
    attrs     = params.expect(upload: %i[filename content_type byte_size md5])
    byte_size = Integer(attrs[:byte_size], exception: false)
    md5       = attrs[:md5].presence

    refuse! 'filename is required.' if attrs[:filename].blank?

    unless byte_size&.between?(1, MultipartUpload.max_byte_size)
      refuse! "byte_size must be between 1 and #{MultipartUpload.max_byte_size}."
    end

    refuse! 'md5 must be 32 hexadecimal digits.' if md5 && !md5.match?(MultipartUpload::MD5_HEX)

    @upload = MultipartUpload.start!(
      user:         current_user,
      filename:     attrs[:filename],
      content_type: attrs[:content_type].presence || 'application/octet-stream',
      byte_size:,
      md5:
    )

    render :show, status: :created
  end

  def show; end

  def part_urls
    numbers = Array(params.expect(part_numbers: [])).map { Integer(it, exception: false) }

    refuse! 'part_numbers is required.' if numbers.empty?
    refuse! "At most #{MAX_PART_URLS} part URLs at a time." if numbers.size > MAX_PART_URLS

    unless numbers.all? { it&.between?(1, @upload.part_count) }
      refuse! "part_numbers must be between 1 and #{@upload.part_count}."
    end

    @urls = @upload.part_urls(numbers.uniq)
  end

  # Every part, each once. The store would complete an upload with a part
  # missing — it only requires them in order — and the object would be the
  # wrong file, found out only when its size does not match.
  def complete
    parts = params.expect(parts: [%i[part_number etag]]).to_h {|part|
      [Integer(part[:part_number], exception: false), part[:etag].to_s]
    }

    unless parts.keys.sort == (1..@upload.part_count).to_a && parts.values.none?(&:blank?)
      refuse! "parts must name every part from 1 to #{@upload.part_count}, each once, with its ETag."
    end

    @upload.complete!(parts)

    render :show, status: :accepted
  rescue Aws::S3::Errors::InvalidPart, Aws::S3::Errors::InvalidPartOrder, Aws::S3::Errors::NoSuchUpload => e
    refuse! "The store refused to complete the upload: #{e.message}"
  end

  def destroy
    @upload.abort!

    head :no_content
  rescue MultipartUpload::AlreadyComplete
    refuse! 'This upload is already complete, and cannot be aborted.'
  end

  private

  def load_upload
    @upload = MultipartUpload.find(params.expect(:token), user: current_user)
  rescue MultipartUpload::NotFound
    raise ActiveRecord::RecordNotFound, "Couldn't find Upload"
  end
end
