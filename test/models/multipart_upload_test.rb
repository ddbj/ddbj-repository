require 'test_helper'

# How a file is cut. The store allows at most 10,000 parts of at most 5 GiB,
# and every part but the last must be 5 MiB or more; within that the parts are
# PART_SIZE, until a file is too big for 10,000 of them.
class MultipartUploadTest < ActiveSupport::TestCase
  def upload(byte_size) = MultipartUpload.new(user_id: 1, key: 'k', upload_id: 'u', filename: 'f', content_type: 't', byte_size:)

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
end
