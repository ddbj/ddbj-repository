require 'test_helper'

class CurationStateTest < ActiveSupport::TestCase
  # --- progress ----------------------------------------------------------

  test 'a request with no submission has not got past Submitted' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    attach_ddbj_record(request)
    request.save!

    state = CurationState.new(request)

    assert_equal :current, state.step_state(:submitted)
    assert_equal :todo,    state.step_state(:applied)
    refute state.curated?
  end

  test 'an applied submission with curation rows sits on Curating' do
    projects(:primary).update!(accession: nil, status: 'curating')

    state = CurationState.new(submission_requests(:bioproject))

    assert_equal :done,    state.step_state(:applied)
    assert_equal :current, state.step_state(:curating)
    assert_equal :todo,    state.step_state(:accession_issued)
  end

  test 'every row accessioned advances to Accession issued' do
    submissions(:biosample).samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))
    samples(:first).update!(accession: 'SAMD00000001', status: 'accession_issued')
    samples(:second).update!(accession: 'SAMD00000002', status: 'accession_issued')

    state = CurationState.new(submission_requests(:biosample))

    assert_equal :current, state.step_state(:accession_issued)
    assert_equal :todo,    state.step_state(:public)
  end

  test 'every row public reaches the last step' do
    submissions(:biosample).samples.update_all(status: Lifecycleable::STATUSES.fetch('public'))

    assert_equal :current, CurationState.new(submission_requests(:biosample)).step_state(:public)
  end

  test 'a failed request marks the step it could not reach' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26', status: :validation_failed)
    attach_ddbj_record(request)
    request.save!

    state = CurationState.new(request)

    assert state.failed?
    assert_equal :failed, state.step_state(:validated)
  end

  # A withdrawn record left the pipeline. Rendering the step it stopped on
  # as "current" claims work is in progress, and the submitter's screen
  # would say a curator is reviewing it.
  test 'a closed record marks its last step as closed, not current' do
    projects(:primary).update!(accession: nil, status: 'withdrawn')

    state = CurationState.new(submission_requests(:bioproject))

    assert state.closed?
    assert_equal :closed, state.step_state(:curating)
    assert_equal :done,   state.step_state(:applied)
    assert_equal :todo,   state.step_state(:public)
  end

  test 'a partly-withdrawn BS submission is not closed' do
    samples(:first).update!(status: 'withdrawn')

    refute CurationState.new(submission_requests(:biosample)).closed?
  end

  # --- aggregate labels --------------------------------------------------

  test 'a mixed BS submission reports the mixture rather than one status' do
    state = CurationState.new(submission_requests(:biosample))

    assert_nil state.uniform_status
    assert_equal 'Mixed (2)', state.status_label
  end

  test 'a uniform BS submission reports the single status' do
    submissions(:biosample).samples.update_all(status: Lifecycleable::STATUSES.fetch('curating'))

    assert_equal 'curating', CurationState.new(submission_requests(:biosample)).status_label
  end

  test 'row_noun names what is being acted on per database' do
    assert_equal 'project', CurationState.new(submission_requests(:bioproject)).row_noun
    assert_equal 'samples', CurationState.new(submission_requests(:biosample)).row_noun
  end

  # --- next action -------------------------------------------------------

  test 'an unread submitter message outranks a pending accession' do
    projects(:primary).update!(accession: nil, status: 'curating')
    request = submission_requests(:bioproject)
    request.messages.create!(user: users(:alice), author_role: 'submitter', body: 'question')

    assert_match(/waiting for a reply/, CurationState.new(request).next_action.title)
  end

  test 'issuable rows become the next action once the thread is clear' do
    projects(:primary).update!(accession: nil, status: 'curating')

    action = CurationState.new(submission_requests(:bioproject)).next_action

    assert_match(/eligible for accession issuance/, action.title)
    assert_equal 'Issue PRJDB for 1 project', action.label
  end

  test 'nothing pending yields no next action' do
    assert_nil CurationState.new(submission_requests(:bioproject)).next_action
  end

  # --- batch -------------------------------------------------------------

  test 'batch answers the same questions as a per-request state' do
    requests = [submission_requests(:bioproject), submission_requests(:biosample), submission_requests(:st26)]
    batched  = CurationState.batch(requests)

    requests.each do |request|
      single = CurationState.new(request)
      state  = batched.fetch(request.id)

      assert_equal single.row_count,          state.row_count,          "row_count for ##{request.id}"
      assert_equal single.statuses.sort,      state.statuses.sort,      "statuses for ##{request.id}"
      assert_equal single.accessioned_count,  state.accessioned_count,  "accessioned_count for ##{request.id}"
      assert_equal single.current_step_index, state.current_step_index, "step for ##{request.id}"
    end
  end

  # The reason for batch existing at all: a list must not pay per row.
  test 'batch reads the curation rows once per model, not once per request' do
    requests = SubmissionRequest.includes(:submission).to_a

    row_queries = count_queries(/FROM "(projects|samples)"/) { CurationState.batch(requests) }

    assert_equal 2, row_queries
  end

  private

  def count_queries(pattern)
    count = 0

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') {|*, payload|
      count += 1 if payload[:sql].match?(pattern)
    }

    yield

    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
