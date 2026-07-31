require 'test_helper'

# The dividing line between the two histories: the patch chain carries
# everything the DDBJ Record carries, and CurationEvent carries what is
# left — which is precisely the set of actions that used to vanish.
class CurationEventTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:biosample)
  end

  def record(**attrs)
    CurationEvent.record!(submission: @submission, actor: 'admin:tanaka', **attrs)
  end

  test 'record! stores only the fields that were touched' do
    event = record(action: :curation_updated, row_count: 3, noun: 'sample', status: 'curating', assignee: nil)

    assert_equal({'noun' => 'sample', 'status' => 'curating'}, event.details)
    assert_equal 3, event.row_count
  end

  test 'the actor namespace is dropped from the sentence' do
    assert_equal 'tanaka', record(action: :curation_updated).actor_label
  end

  test 'a status change reads as a sentence with the row count' do
    event = record(action: :curation_updated, row_count: 1842, noun: 'sample', status: 'curating')

    assert_equal 'set 1,842 samples to curating', event.summary
  end

  test 'status and assignee in one save read as one sentence' do
    event = record(action: :curation_updated, row_count: 1842, noun: 'sample', status: 'curating', assignee: 'tanaka')

    assert_equal 'set 1,842 samples to curating and assigned them to tanaka', event.summary
  end

  test 'an assignee-only change names the rows rather than saying them' do
    event = record(action: :curation_updated, row_count: 1, noun: 'project', assignee: 'tanaka')

    assert_equal 'assigned 1 project to tanaka', event.summary
  end

  test 'a comment-only change says so' do
    event = record(action: :curation_updated, curator_comment: true)

    assert_equal 'updated the curator comment', event.summary
  end

  test 'accession issuance names the prefix' do
    event = record(action: :accession_issued, row_count: 1842, prefix: 'SAMD')

    assert_equal 'issued 1,842 SAMD accessions', event.summary
  end

  test 'accession issuance stays singular for one' do
    event = record(action: :accession_issued, row_count: 1, prefix: 'PRJDB')

    assert_equal 'issued 1 PRJDB accession', event.summary
  end

  test 'an unknown action is rejected' do
    assert_raises ActiveRecord::RecordInvalid do
      record(action: 'nonsense')
    end
  end

  test 'events die with their submission' do
    record(action: :curation_updated)

    assert_difference 'CurationEvent.count', -1 do
      @submission.destroy
    end
  end
end
