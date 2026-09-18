require 'test_helper'
require 'net/http'

# Resumable uploads, end to end against the store the suite runs on: the parts
# are PUT to the signed URLs the way a client would, so what is exercised is
# the store's multipart behaviour and not a stub of it.
class UploadsTest < ActionDispatch::IntegrationTest
  # Parts at the store's own minimum rather than the production size, so a
  # file of two parts is 5 MiB and not 32.
  PART = MultipartUpload::STORE_MINIMUM_PART

  setup do
    @alice = users(:alice)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @file = Random.bytes(PART + 1234)
    @keys = []
  end

  # What a test PUTs straight to the store passes no Active Storage service,
  # so the suite-wide cleanup does not see it.
  teardown do
    client = MultipartUpload.client
    bucket = MultipartUpload.bucket

    @keys.each do |key|
      client.list_multipart_uploads(bucket:, prefix: key).uploads.each do |upload|
        client.abort_multipart_upload(bucket:, key:, upload_id: upload.upload_id)
      end

      client.delete_object(bucket:, key:)
    end
  end

  test 'a file sent in parts becomes a blob, checked against the MD5 it was declared with' do
    with_small_parts do
      upload = start(md5: Digest::MD5.hexdigest(@file))

      assert_equal 'uploading', upload['state']
      assert_equal 2,           upload['part_count']
      assert_empty upload['parts']

      etags = send_parts(upload, 1 => @file.byteslice(0, PART), 2 => @file.byteslice(PART..))

      post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json

      assert_conform_schema 202
      assert_equal 'verifying', response.parsed_body['state']

      # Between completion and the Blob, the state is observable on its own.
      get upload_path(upload['token'])

      assert_equal 'verifying', response.parsed_body['state']

      perform_enqueued_jobs

      get upload_path(upload['token'])

      assert_conform_schema 200
      assert_equal 'ready', response.parsed_body['state']

      blob = ActiveStorage::Blob.find_signed!(response.parsed_body['signed_blob_id'])

      assert_equal @file.bytesize,                    blob.byte_size
      assert_equal Digest::MD5.base64digest(@file),   blob.checksum
      assert_equal @file,                             blob.download

      # And it waits in the uploader's unassigned files, where nothing collects it.
      get unassigned_files_path

      assert_equal [blob.signed_id], response.parsed_body.pluck('signed_blob_id')
    end
  end

  # A client whose completion request is lost — a dropped response, a 503 from
  # the proxy — sends it again. If the store answered the second one as a
  # mistake, the file would be thrown away while it was being verified.
  test 'completing an upload again is answered as done' do
    with_small_parts do
      upload = start(md5: Digest::MD5.hexdigest(@file))
      etags  = send_parts(upload, 1 => @file.byteslice(0, PART), 2 => @file.byteslice(PART..))
      parts  = etags.map {|n, e| {part_number: n, etag: e} }

      post complete_upload_path(upload['token']), params: {parts:}, as: :json

      assert_conform_schema 202

      post complete_upload_path(upload['token']), params: {parts:}, as: :json

      assert_conform_schema 202
      assert_equal 'verifying', response.parsed_body['state']

      perform_enqueued_jobs

      get upload_path(upload['token'])

      assert_equal 'ready', response.parsed_body['state']
      assert_equal @file,   ActiveStorage::Blob.find_signed!(response.parsed_body['signed_blob_id']).download
    end
  end

  # The reason it is resumable. A client that stopped asks what the store has
  # and sends only the rest.
  test 'an upload picked up again sends only the parts the store does not have' do
    with_small_parts do
      upload = start

      send_parts(upload, 1 => @file.byteslice(0, PART))

      get upload_path(upload['token'])

      assert_conform_schema 200

      held = response.parsed_body['parts']

      assert_equal [1], held.pluck('part_number')

      etags = held.to_h { [it['part_number'], it['etag']] }.merge(send_parts(upload, 2 => @file.byteslice(PART..)))

      post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
      perform_enqueued_jobs

      get upload_path(upload['token'])

      assert_equal 'ready', response.parsed_body['state']
    end
  end

  # The checksum is what the store holds, not what the client said: a file
  # that does not match its declared MD5 is not kept.
  test 'a finished object that is not the declared file is removed' do
    upload = start(md5: '0' * 32)

    etags = send_parts(upload, 1 => @file)

    post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
    perform_enqueued_jobs

    get upload_path(upload['token'])

    assert_equal 'rejected', response.parsed_body['state']
    assert_nil ActiveStorage::Blob.find_by(key: @keys.last)
  end

  # Every part named, and still not the file it was started as: the parts add up
  # to something else. It cannot become a Blob of the size it claims.
  test 'a finished object that is not the size it was started with is removed' do
    upload = start(byte_size: @file.bytesize + 1)
    etags  = send_parts(upload, 1 => @file)

    post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
    perform_enqueued_jobs

    get upload_path(upload['token'])

    assert_equal 'rejected', response.parsed_body['state']
  end

  # The store would complete an upload with a part missing, and make a file of
  # the rest.
  test 'completing with a part missing is refused' do
    with_small_parts do
      upload = start
      etags  = send_parts(upload, 1 => @file.byteslice(0, PART))

      with_exceptions_app do
        post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
      end

      assert_conform_schema 422

      get upload_path(upload['token'])

      assert_equal 'uploading', response.parsed_body['state']
    end
  end

  # An uppercase MD5 is the same MD5.
  test 'a declared MD5 matches whatever case it is written in' do
    upload = start(md5: Digest::MD5.hexdigest(@file).upcase)
    etags  = send_parts(upload, 1 => @file)

    post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
    perform_enqueued_jobs

    get upload_path(upload['token'])

    assert_equal 'ready', response.parsed_body['state']
  end

  test 'a file started without a content type is stored as octet-stream' do
    post uploads_path, params: {upload: {filename: 'reads.fastq', byte_size: @file.bytesize}}, as: :json

    upload = response.parsed_body
    @keys << MultipartUpload.encryptor.decrypt_and_verify(upload['token'], purpose: :multipart_upload).fetch('key')

    etags = send_parts(upload, 1 => @file)

    post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
    perform_enqueued_jobs

    assert_equal 'application/octet-stream', ActiveStorage::Blob.find_by!(key: @keys.last).content_type
  end

  # `parts` lists every copy of a part the store holds. A client that sent that
  # list back meant one of them, and which is not for the server to guess.
  test 'completing with a part named twice is refused' do
    upload = start
    etags  = send_parts(upload, 1 => @file)
    etag   = etags.fetch(1)

    with_exceptions_app do
      post complete_upload_path(upload['token']), params: {parts: [{part_number: 1, etag:}, {part_number: 1, etag:}]}, as: :json
    end

    assert_conform_schema 422
  end

  # The store's minimum is for every part but the last. A client that cut the
  # file its own way hears it from the store, as a refusal and not a 500.
  test 'a part under the store minimum is refused at completion' do
    with_small_parts do
      upload = start
      etags  = send_parts(upload, 1 => @file.byteslice(0, 1.megabyte), 2 => @file.byteslice(1.megabyte..))

      with_exceptions_app do
        post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json
      end

      assert_conform_schema 422
    end
  end

  # Bytes, not characters: the name travels in the token, and the token in the
  # path. A hundred Japanese characters are within the schema's 255 and three
  # hundred bytes.
  test 'a filename longer than 255 bytes is refused, however few characters it is' do
    with_exceptions_app do
      post uploads_path, params: {upload: {filename: 'あ' * 100, byte_size: 1}}, as: :json
    end

    assert_conform_schema 422
  end

  # Not a float truncated to a whole number, and not "0x10" read as sixteen.
  test 'a number that is not a whole number is refused, not rounded' do
    with_exceptions_app { post uploads_path, params: {upload: {filename: 'reads.fastq', byte_size: '0x10'}}, as: :json }

    assert_response :unprocessable_content

    upload = start

    with_exceptions_app { post part_urls_upload_path(upload['token']), params: {part_numbers: [1.9]}, as: :json }

    assert_response :unprocessable_content
  end

  # Nothing about the request was wrong, and the same request may work shortly.
  test 'a store that does not answer is a 503' do
    upload = start

    down = Object.new
    down.define_singleton_method(:head_object) {|**| raise Seahorse::Client::NetworkingError, SocketError.new('down') }

    MultipartUpload.stub(:client, down) do
      with_exceptions_app { get upload_path(upload['token']) }
    end

    assert_conform_schema 503
  end

  # A token of a shape this code does not know — from before a change to what
  # it carries — is a 404, not a 500.
  test 'a token of an unfamiliar shape is not found' do
    upload = start
    attrs  = MultipartUpload.encryptor.decrypt_and_verify(upload['token'], purpose: :multipart_upload)
    odd    = MultipartUpload.encryptor.encrypt_and_sign(attrs.merge('extra' => 1), purpose: :multipart_upload, expires_in: 1.hour)

    with_exceptions_app { get upload_path(odd) }

    assert_conform_schema 404
  end

  test 'part URLs are only for parts the upload has' do
    upload = start

    with_exceptions_app { post part_urls_upload_path(upload['token']), params: {part_numbers: [2]}, as: :json }

    assert_conform_schema 422

    with_exceptions_app { post part_urls_upload_path(upload['token']), params: {part_numbers: (1..101).to_a}, as: :json }

    assert_response :unprocessable_content
  end

  test 'an upload not yet complete can be abandoned' do
    upload = start

    delete upload_path(upload['token'])

    assert_response :no_content

    get upload_path(upload['token'])

    assert_equal 'rejected', response.parsed_body['state']
  end

  # A curator can upload for somebody, but what they sent is theirs to discard.
  test 'abandoning is refused while acting as another account' do
    upload = start

    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    with_exceptions_app { delete upload_path(upload['token']) }

    assert_conform_schema 403

    get upload_path(upload['token'])

    assert_equal 'uploading', response.parsed_body['state']
  end

  # Aborting the upload of a finished object can delete the object's data in
  # the store (seaweedfs/seaweedfs#10663), so it is not offered.
  test 'a completed upload cannot be abandoned' do
    upload = start
    etags  = send_parts(upload, 1 => @file)

    post complete_upload_path(upload['token']), params: {parts: etags.map {|n, e| {part_number: n, etag: e} }}, as: :json

    with_exceptions_app { delete upload_path(upload['token']) }

    assert_conform_schema 422

    perform_enqueued_jobs

    assert_equal @file, ActiveStorage::Blob.find_by!(key: @keys.last).download
  end

  # The token names the upload; it does not let anybody in.
  test "somebody else's upload is not found" do
    upload = start

    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app { get upload_path(upload['token']) }

    assert_conform_schema 404
  end

  test 'a token that has been tampered with is not found' do
    upload = start

    with_exceptions_app { get upload_path(upload['token'].reverse) }

    assert_conform_schema 404
  end

  # The same seven days the store gives an unfinished upload.
  test 'a token is good for seven days from the start' do
    upload = start

    travel(MultipartUpload::RESUMABLE_FOR + 1.minute) { with_exceptions_app { get upload_path(upload['token']) } }

    assert_conform_schema 404
  end

  # Larger than the store could hold in its 10,000 parts of at most 5 GiB. An
  # empty file is the schema's to refuse, and is.
  test 'a file larger than the store can take is refused' do
    with_exceptions_app do
      post uploads_path, params: {upload: {filename: 'reads.fastq', byte_size: MultipartUpload.max_byte_size + 1}}, as: :json
    end

    assert_conform_schema 422
  end

  test 'a declared MD5 that is not one is refused' do
    with_exceptions_app do
      post uploads_path, params: {upload: {filename: 'reads.fastq', byte_size: 1, md5: 'not an md5'}}, as: :json
    end

    assert_conform_schema 422
  end

  private

  def start(md5: nil, byte_size: @file.bytesize)
    post uploads_path, params: {upload: {filename: 'reads.fastq', content_type: 'text/plain', byte_size:, md5:}.compact}, as: :json

    assert_conform_schema 201

    response.parsed_body.tap {|upload|
      @keys << MultipartUpload.encryptor.decrypt_and_verify(upload['token'], purpose: :multipart_upload).fetch('key')
    }
  end

  def with_small_parts(&)
    MultipartUpload.stub(:part_size_floor, PART, &)
  end

  # PUTs each part to its signed URL, as a client does, and returns the ETags
  # the store answered with.
  def send_parts(upload, bodies)
    post part_urls_upload_path(upload['token']), params: {part_numbers: bodies.keys}, as: :json

    assert_conform_schema 200

    urls = response.parsed_body.to_h { [it['part_number'], it['url']] }

    bodies.to_h {|number, body|
      uri = URI(urls.fetch(number))

      answer = Net::HTTP.start(uri.host, uri.port) {|http|
        http.request(Net::HTTP::Put.new(uri, 'Content-MD5' => Digest::MD5.base64digest(body)).tap { it.body = body })
      }

      assert_equal '200', answer.code, "PUT part #{number}: #{answer.body}"

      [number, answer['etag']]
    }
  end
end
