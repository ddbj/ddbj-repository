require 'test_helper'

class DRASubmissionTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @row = dra_submissions(:dra)
    @row.update! status: :private
  end

  def record = JSON.parse(file_fixture('dra/record/DRA000001.json').read).merge('relations' => [])

  # D-way kept a submission private until what it published was valid,
  # rather than call it public and publish nothing.
  test 'a DRA submission is not made public where what it would publish is not valid' do
    @row.submission.append_update! record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }, actor: 'test'

    error = assert_raises(DRASubmission::Unpublishable) { DRASubmission.where(id: @row.id).move_to_status!('public') }

    assert_match(/\ADRA000001: experiment: .*LIBRARY_STRATEGY/, error.message)
    assert @row.reload.status_private?
    assert_nil @row.first_published_at
    assert_empty @row.submission.request.messages.system_role
    assert_no_enqueued_emails
  end

  # The flash is a cookie of 4 KB, and the XSD's message for a wrong value
  # lists every value it takes.
  test 'a refusal is summed up short enough for a screen, and said whole for the record' do
    error = DRASubmission::Unpublishable.new((1..12).map { [format('DRA%06d', it), "experiment: #{'x' * 2_000}"] })

    assert_equal 12, error.message.lines.size
    assert_operator error.summary.size, :<, 500
    assert error.summary.start_with?('DRA000001, DRA000002, DRA000003, DRA000004, DRA000005, DRA000006, DRA000007, DRA000008, DRA000009, DRA000010, …: experiment: xxx')
    assert error.summary.end_with?('(and 11 more)')
  end

  test 'nor where it has no record to publish' do
    error = assert_raises(DRASubmission::Unpublishable) { DRASubmission.where(id: @row.id).move_to_status!('public') }

    assert_equal 'DRA000001: it has no record to publish', error.message
  end

  test 'one that publishes is made public' do
    @row.submission.append_update! record, actor: 'test'

    assert_equal 1, DRASubmission.where(id: @row.id).move_to_status!('public')
    assert @row.reload.status_public?
  end

  # Only the way into public is asked: out of it, nothing is published.
  test 'any other status is set whatever it would publish' do
    assert_equal 1, DRASubmission.where(id: @row.id).move_to_status!('temporarily_suppressed')
  end
end
