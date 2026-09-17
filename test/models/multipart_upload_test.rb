require 'test_helper'

# How a file is cut. The store allows at most 10,000 parts of at most 5 GiB,
# and every part but the last must be 5 MiB or more; within that the parts are
# PART_SIZE, until a file is too big for 10,000 of them.
class MultipartUploadTest < ActiveSupport::TestCase
  def upload(byte_size, started_at: Time.current.to_i)
    MultipartUpload.new(user_id: users(:alice).id, key: 'k', upload_id: 'u', filename: 'f', content_type: 't', byte_size:, md5: nil, started_at:)
  end

  test 'a file of any ordinary size is cut into parts of the standard size' do
    assert_equal MultipartUpload::PART_SIZE, upload(1).part_size
    assert_equal 1,                          upload(1).part_count

    assert_equal 3, upload((2 * MultipartUpload::PART_SIZE) + 1).part_count
  end

  # 160 GiB is where 16 MiB parts reach 10,000. Past it the parts grow, whole
  # MiB at a time, so the count never goes over.
  test 'a file too large for 10,000 standard parts gets larger parts' do
    size   = 500.gigabytes
    parted = upload(size)

    assert_operator parted.part_size, :>, MultipartUpload::PART_SIZE
    assert_equal 0,                      parted.part_size % 1.megabyte
    assert_operator parted.part_count, :<=, MultipartUpload::MAX_PARTS
  end

  test 'the largest file there can be still fits, in parts the store accepts' do
    largest = upload(MultipartUpload.max_byte_size)

    assert_operator largest.part_count, :<=, MultipartUpload::MAX_PARTS
    assert_operator largest.part_size,  :<=, MultipartUpload::MAX_PART
  end

  # Issued again on every response, and still expiring when the first one did.
  # With a fresh `expires_in` each time, a client that kept asking kept its
  # upload for ever.
  test 'a token issued again later expires when the first one does' do
    first = upload(1).token

    later = travel(6.days) { MultipartUpload.find(first, user: users(:alice)).token }

    travel(MultipartUpload::RESUMABLE_FOR + 1.minute) do
      assert_raises(MultipartUpload::NotFound) { MultipartUpload.find(later, user: users(:alice)) }
    end
  end

  # Encrypted, because it is written into URL paths and so into logs. Signed
  # alone, every segment decodes to the JSON it carries.
  test 'a token does not show what it carries' do
    carried = MultipartUpload.new(
      user_id: users(:alice).id, key: 'k', upload_id: 'u', filename: 'patient-0042-tumour.fastq',
      content_type: 't', byte_size: 1, md5: nil, started_at: Time.current.to_i
    )

    decoded = carried.token.split('--').map { Base64.urlsafe_decode64(it) }

    assert decoded.none? { it.include?('patient-0042') }, 'the filename is readable in the token'
  end
end
