require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'sync_emails! fills accounts that have never logged in' do
    users(:carol).update!(email: nil)

    stub_cloakman_lookup [{uid: 'carol', email: 'carol@example.com'}], uids: %w[carol]

    assert_equal 1, User.sync_emails!(User.where(uid: 'carol'))
    assert_equal 'carol@example.com', users(:carol).reload.email
  end

  # Cloakman is the authority: an address it no longer holds must not
  # survive locally, or mail keeps going to the old mailbox.
  test 'sync_emails! clears an address Cloakman no longer has' do
    stub_cloakman_lookup [{uid: 'alice', email: nil}], uids: %w[alice]

    assert_equal 1, User.sync_emails!(User.where(uid: 'alice'))
    assert_nil users(:alice).reload.email
  end

  test 'sync_emails! reports no change when the address already matches' do
    stub_cloakman_lookup [{uid: 'alice', email: 'alice@example.com'}], uids: %w[alice]

    assert_equal 0, User.sync_emails!(User.where(uid: 'alice'))
  end

  # The two jobs that tidy the list ask this, and both would take the wrong
  # rows if either half of it went missing: `files` is also what a message's
  # attachments are called, and an account may come to hold attachments of
  # other kinds.
  test 'unassigned_file_attachments is the list, and nothing else' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('ACGT'), filename: 'reads.fastq', content_type: 'text/plain')
    mine = users(:alice).unassigned_files_attachments.create!(blob:)

    # Another kind of attachment on the same account, and the same name on
    # another kind of record. Written straight in: the point is the pair of
    # columns, not how either row would come about.
    ActiveStorage::Attachment.create!(record: users(:alice), name: 'something_else', blob:)
    ActiveStorage::Attachment.create!(record: submission_requests(:st26), name: 'unassigned_files', blob:)

    assert_equal [mine.id], User.unassigned_file_attachments.pluck(:id)
  end

  test 'sync_emails! leaves users Cloakman did not return alone' do
    stub_cloakman_lookup [], uids: %w[alice]

    assert_equal 0, User.sync_emails!(User.where(uid: 'alice'))
    assert_equal 'alice@example.com', users(:alice).reload.email
  end
end
