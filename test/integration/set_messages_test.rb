require 'test_helper'

# The set's own thread: one conversation about the bundle, which every
# member is party to.
#
# The line this draws — and the reason the file exists — is that being in
# a set makes you party to the SET's conversation, and to nothing else.
# The per-submission threads stay between their owner and DDBJ, and
# test/integration/set_sharing_boundary_test.rb holds that half.
class SetMessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @alice = users(:alice)
    @carol = users(:carol)
    @bob   = users(:bob) # curator

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"
  end

  test 'a member posts and the whole set reads it' do
    assert_difference 'SubmissionSetMessage.count', 1 do
      post set_messages_path(@set),
           params:  {submission_set_message: {body: 'Are these two projects one submission or two?'}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 201
    assert_equal 'member',      response.parsed_body['author_role']
    assert_equal @alice.uid,    response.parsed_body['author_uid']

    as @carol

    get set_messages_path(@set)

    assert_conform_schema 200
    assert_equal ['Are these two projects one submission or two?'], response.parsed_body.map { it['body'] }
  end

  test 'a set you are not in has no thread to read or write' do
    theirs = SubmissionSet.create!(name: 'Somebody else', owner: @carol)

    with_exceptions_app { get set_messages_path(theirs) }
    assert_response :not_found

    with_exceptions_app do
      post set_messages_path(theirs), params: {submission_set_message: {body: 'hello'}}.to_json, headers: JSON_HEADERS
    end

    assert_response :not_found
  end

  # An invitation nobody has walked through is not membership — nothing
  # is shared until they do, and that has to include the conversation.
  test 'an outstanding invitation reads nothing' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Members only')

    invited = users(:dave)
    @set.members.create!(email: invited.email, invited_by: @alice)

    as invited

    with_exceptions_app { get set_messages_path(@set) }

    assert_response :not_found
  end

  test 'an attachment is readable by every member and by nobody else' do
    message = @set.messages.create!(user: @alice, author_role: :member, body: 'Here it is')
    message.files.attach(io: StringIO.new('x'), filename: 'notes.txt', content_type: 'text/plain')

    file = message.files.first

    as @carol

    get set_message_file_path(@set, message, file.id)
    assert_response :redirect

    as users(:dave)

    with_exceptions_app { get set_message_file_path(@set, message, file.id) }
    assert_response :not_found
  end

  test 'an attachment from another set is not found rather than served' do
    mine   = @set.messages.create!(user: @alice, author_role: :member, body: 'Mine')
    other  = SubmissionSet.create!(name: 'Other', owner: @alice)
    theirs = other.messages.create!(user: @alice, author_role: :member, body: 'Theirs')

    theirs.files.attach(io: StringIO.new('x'), filename: 'notes.txt', content_type: 'text/plain')

    with_exceptions_app { get set_message_file_path(@set, mine, theirs.files.first.id) }

    assert_response :not_found
  end

  # Reading is one person's business. The request thread can hold "the
  # submitter has dealt with this" in one timestamp because there is one
  # submitter; a set has as many members as it has.
  test 'marking read moves this member and nobody else' do
    curator_message = @set.messages.create!(user: @bob, author_role: :curator, body: 'Which of these is the parent?')

    get sets_path
    assert_equal 1, response.parsed_body.sole['unread_message_count'], 'waiting on alice'

    post read_set_messages_path(@set), params: {through_id: curator_message.id}.to_json, headers: JSON_HEADERS
    assert_response :no_content

    get sets_path
    assert_equal 0, response.parsed_body.sole['unread_message_count']

    as @carol

    get sets_path
    assert_equal 1, response.parsed_body.sole['unread_message_count'], 'carol has not read it'
  end

  # Answering is the work, so it settles the thread for the whole set —
  # the same rule the curator side has always had, in the other
  # direction.
  test 'a colleague answering settles it for everyone' do
    @set.messages.create!(user: @bob, author_role: :curator, body: 'Which of these is the parent?')

    as @carol

    post set_messages_path(@set),
         params:  {submission_set_message: {body: 'PRJDB1234 is.'}}.to_json,
         headers: JSON_HEADERS

    assert_response :created

    as @alice

    get sets_path

    assert_equal 0, response.parsed_body.sole['unread_message_count'], 'carol answered for the set'
  end

  test 'a message with neither body nor file is refused' do
    with_exceptions_app do
      post set_messages_path(@set), params: {submission_set_message: {body: '   '}}.to_json, headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
  end

  # Posting notifies the curators following the set. Nobody following
  # means nothing goes out — the set reaches the queue on its own, which
  # is how a thread nobody has answered yet is found at all.
  test 'posting tells the curators who follow the set, and only them' do
    perform_enqueued_jobs do
      assert_no_emails do
        post set_messages_path(@set), params: {submission_set_message: {body: 'Anyone?'}}.to_json, headers: JSON_HEADERS
      end

      @set.subscribe!(@bob)

      assert_emails 1 do
        post set_messages_path(@set), params: {submission_set_message: {body: 'Still anyone?'}}.to_json, headers: JSON_HEADERS
      end
    end

    assert_equal [@bob.email], ActionMailer::Base.deliveries.last.to
  end

  private

  def as(user)
    default_headers['Authorization'] = "Bearer #{user.api_key}"
  end
end
