require 'test_helper'

# Service-level checks for the parts of a curation save that are about cost
# and dispatch rather than about the resulting rows — those are covered
# through the controller in test/integration/admin/curations_test.rb.
class CurationUpdateTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:bioproject)
    @submission.append_update!(
      {'schema_version' => 'v3', 'submission' => {'hold_date' => '2026-12-31'}},
      actor:  'test-seed',
      source: :manual
    )
  end

  def call(params) = CurationUpdate.new(submission: @submission, actor: 'admin:bob', params:).call

  # The rail posts hold_date on every save. Reaching `append_update!` only
  # to diff to nothing costs a full chain replay plus two canonicalisation
  # passes — tens of seconds on a 100K-sample record — so a save that did
  # not move the date must short-circuit before that.
  test 'an unchanged hold date never reaches the chain' do
    @submission.define_singleton_method(:append_update!) {|*, **|
      raise 'append_update! must not be reached for an unchanged hold date'
    }

    result = call(hold_date: '2026-12-31', curator_comment: 'only the comment moved')

    assert_equal ['curator comment'], result.changes
    assert_equal 'only the comment moved', @submission.reload.curator_comment
  end

  test 'a changed hold date does reach the chain' do
    assert_difference '@submission.updates.count', 1 do
      result = call(hold_date: '2027-01-31')

      assert_equal ['hold date=2027-01-31'], result.changes
    end
  end

  test 'clearing a hold date reaches the chain' do
    assert_difference '@submission.updates.count', 1 do
      assert_equal ['hold date=—'], call(hold_date: '').changes
    end
  end

  # Absence means "leave alone" — the reason the rail can omit the field
  # entirely when the chain cannot be replayed.
  test 'omitting the key touches neither the chain nor the projection' do
    assert_no_difference '@submission.updates.count' do
      assert_empty call(curator_comment: 'note').changes - ['curator comment']
    end
  end

  test 'a hold date that is not a strict ISO date is refused before any write' do
    assert_no_difference '@submission.updates.count' do
      assert_raises(CurationUpdate::Refused) { call(hold_date: '2026/12/31', curator_comment: 'note') }
    end

    assert_nil @submission.reload.curator_comment, 'a refused save must not half-apply'
  end
end
