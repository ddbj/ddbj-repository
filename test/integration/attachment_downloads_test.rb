require 'test_helper'

# Who can fetch which file, now that Active Storage's own blob route is
# off and every download goes through a route that names both the record
# and the attachment.
#
# The property these are defending: a URL is not a credential. Each of
# these requests is authorised when it arrives, so access that has been
# taken away is access that has stopped working — which is what
# "removing a member takes their submissions with them" has to mean about
# the files as well as the rows.
class AttachmentDownloadsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    @submission_request = submission_requests(:bioproject) # owned by :alice
    attach_ddbj_record @submission_request
    attach_submission_files @submission_request.submission

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"
  end

  test 'Active Storage no longer serves blobs on its own route' do
    assert_not Rails.application.routes.url_helpers.respond_to?(:rails_blob_path)
    assert_not Rails.application.routes.url_helpers.respond_to?(:rails_service_blob_path)
  end

  test 'the owner gets a short-lived redirect to storage' do
    get submission_request_file_path(@submission_request, 'ddbj_record')

    assert_response :redirect
    assert_match %r{/rails/active_storage/disk/}, response.location
  end

  test 'the submission files follow the same rule' do
    %w[ddbj_record flatfile_na flatfile_aa].each do |name|
      get submission_file_path(@submission_request.submission, name)

      assert_response :redirect
    end
  end

  test 'somebody else gets nothing' do
    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app { get submission_request_file_path(@submission_request, 'ddbj_record') }

    assert_response :not_found
  end

  test 'and nobody at all gets nothing' do
    default_headers.delete('Authorization')

    get submission_request_file_path(@submission_request, 'ddbj_record')

    assert_response :unauthorized
  end

  # The point of the whole exercise: reading it through a shared set is a
  # thing that can be taken away, and taking it away has to reach the
  # files.
  test 'a set member can fetch it, and stops being able to when they are removed' do
    set = SubmissionSet.create!(name: 'Deep sea study', owner: @carol)
    set.members.create!(user: @alice, invited_by: @carol, joined_at: Time.current)
    set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    get submission_request_file_path(@submission_request, 'ddbj_record')
    assert_response :redirect

    set.members.find_by!(user_id: @alice.id).remove!

    with_exceptions_app { get submission_request_file_path(@submission_request, 'ddbj_record') }
    assert_response :not_found
  end

  test 'an attachment no route names has no way in' do
    assert_raises(ActionController::UrlGenerationError) do
      submission_file_path(@submission_request.submission, 'cached_materialised_record')
    end
  end

  # Message attachments are owner-scoped, not readable-scoped: the
  # conversation is between one submitter and DDBJ.
  test 'a set member cannot fetch a message attachment' do
    message = @submission_request.messages.create!(user: @alice, author_role: :submitter, body: 'Here it is')
    message.files.attach(io: StringIO.new('x'), filename: 'note.txt', content_type: 'text/plain')

    set = SubmissionSet.create!(name: 'Deep sea study', owner: @carol)
    set.members.create!(user: @alice, invited_by: @carol, joined_at: Time.current)
    set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    get submission_request_message_file_path(@submission_request, message, message.files.first.id)
    assert_response :redirect

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app { get submission_request_message_file_path(@submission_request, message, message.files.first.id) }
    assert_response :not_found
  end

  test 'a message attachment from another thread is not found rather than served' do
    mine   = @submission_request.messages.create!(user: @alice, author_role: :submitter, body: 'Mine')
    theirs = submission_requests(:st26).messages.create!(user: @alice, author_role: :submitter, body: 'Theirs')

    theirs.files.attach(io: StringIO.new('x'), filename: 'note.txt', content_type: 'text/plain')

    with_exceptions_app do
      get submission_request_message_file_path(@submission_request, mine, theirs.files.first.id)
    end

    assert_response :not_found
  end

  # A reviewer's files ride on the share token, so revoking the share
  # revokes them. Under Active Storage's own route the URLs they had
  # collected went on working for ever, which made "disable the link"
  # mean less than it says.
  test 'a reviewer fetches on the share token, and loses the files with it' do
    access = @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)

    default_headers.delete('Authorization')

    %w[ddbj_record submission_record flatfile_na flatfile_aa].each do |name|
      get review_file_path(access.token, name)

      assert_response :redirect, name
    end

    access.destroy!

    with_exceptions_app { get review_file_path(access.token, 'ddbj_record') }

    assert_response :not_found
  end

  test 'an expired share is as good as no share' do
    access = @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)
    access.update_columns(expires_at: 1.day.ago)

    default_headers.delete('Authorization')

    with_exceptions_app { get review_file_path(access.token, 'ddbj_record') }

    assert_response :not_found
  end

  # The reviewer view never shows the conversation, so it must not be a
  # way to its attachments either.
  test 'the reviewer route names only the files the reviewer view shows' do
    assert_raises(ActionController::UrlGenerationError) do
      review_file_path('sometoken', 'patch')
    end
  end

  # Active Storage's own direct-upload endpoint is public by design. Ours
  # is not: it mints a blob row and a presigned PUT, and redrawing it
  # unauthenticated would let anybody fill the bucket.
  test 'direct upload needs a caller' do
    body = {
      blob: {
        filename:     'x.json',
        byte_size:    1,
        checksum:     Digest::MD5.base64digest('x'),
        content_type: 'application/json'
      }
    }

    default_headers.delete('Authorization')

    post direct_uploads_path, params: body.to_json, headers: {'Content-Type' => 'application/json'}

    assert_response :unauthorized

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    post direct_uploads_path, params: body.to_json, headers: {'Content-Type' => 'application/json'}

    assert_response :success
    assert response.parsed_body['signed_id'].present?
  end

  # Caching the redirect for as long as the URL it points at is valid
  # would mean a second click inside that window never comes back here —
  # and coming back here is the whole point. A membership revoked a
  # minute ago has to be a download that stops, not one that stops in
  # five minutes.
  test 'the redirect is never cached' do
    get submission_request_file_path(@submission_request, 'ddbj_record')

    assert_response :redirect
    assert_match(/no-cache|no-store/, response.headers['Cache-Control'].to_s)
  end

  # A browser cannot put an Authorization header on an anchor and this
  # API takes no cookies, so the web client asks for the address instead
  # of following the redirect. Same check either way.
  test 'the address can be asked for instead of followed' do
    get submission_request_file_path(@submission_request, 'ddbj_record', as: 'url')

    assert_response :success
    assert_match %r{/rails/active_storage/disk/}, response.parsed_body.fetch('url')

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app { get submission_request_file_path(@submission_request, 'ddbj_record', as: 'url') }

    assert_response :not_found
  end
end
