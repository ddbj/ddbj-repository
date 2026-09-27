require 'test_helper'

# How drmdb's versions and groups become a history. The shape is one real
# submission's (drmdb sub_id 55268): a first send, a second adding an
# experiment and a run, a third, and a curator's edits after the last.
class DRA::StagingClientTest < ActiveSupport::TestCase
  Meta   = DRA::StagingClient::Meta
  Member = DRA::StagingClient::Member

  def at(time) = Time.zone.parse("2025-#{time}")

  def member(acc_id, acc_type) = Member.new(acc_id:, acc_type:, acc_no: acc_id)

  setup do
    submission  = member(1, 'DRA')
    experiment  = member(2, 'DRX')
    run         = member(3, 'DRR')
    experiment2 = member(4, 'DRX')
    run2        = member(5, 'DRR')
    dropped     = member(6, 'DRR')

    @groups = [
      {'grp_id' => 10, 'date' => at('05-31 13:58:15')},
      {'grp_id' => 11, 'date' => at('06-04 11:24:08')},
      {'grp_id' => 12, 'date' => at('06-04 14:30:38')}
    ]

    @members = {
      10 => [submission, experiment, run, dropped],
      11 => [submission, experiment, run, experiment2, run2],
      12 => [submission, experiment, run, experiment2, run2]
    }

    @metas = [
      [101, 1, 'submission', '05-31 13:57:47'], [102, 1, 'submission', '06-04 11:23:33'], [103, 1, 'submission', '06-04 14:53:01'], [104, 1, 'submission', '06-27 08:36:53'],
      [201, 2, 'experiment', '05-31 13:57:47'], [202, 2, 'experiment', '06-04 11:23:33'], [203, 2, 'experiment', '06-04 14:53:01'],
      [301, 3, 'run',        '05-31 13:57:47'], [302, 3, 'run',        '06-04 11:23:33'], [303, 3, 'run',        '06-04 14:30:01'], [304, 3, 'run', '06-04 14:53:01'],
      [401, 4, 'experiment', '06-04 11:23:33'], [402, 4, 'experiment', '06-04 14:53:01'],
      [501, 5, 'run',        '06-04 11:23:33'], [502, 5, 'run',        '06-04 14:30:01'], [503, 5, 'run', '06-04 14:53:01'],
      [601, 6, 'run',        '05-31 13:57:47']
    ].map { Meta.new(meta_id: _1, acc_id: _2, kind: _3, saved_at: at(_4)) }
  end

  test 'each save is a version, holding the objects of the send that followed it' do
    states = DRA::StagingClient.states(groups: @groups, members: @members, metas: @metas)

    assert_equal(
      [
        # The first send; the run the second leaves out is still here.
        [at('05-31 13:57:47'), [101, 201, 301, 601]],
        # Saved a minute before the send that adds the new experiment and run.
        [at('06-04 11:23:33'), [102, 202, 401, 302, 501]],
        [at('06-04 14:30:01'), [102, 202, 401, 303, 502]],
        # After the last send: a group of objects no later send changes.
        [at('06-04 14:53:01'), [103, 203, 402, 304, 503]],
        [at('06-27 08:36:53'), [104, 203, 402, 304, 503]]
      ],
      states.map {|saved_at, state| [saved_at, state.map(&:meta_id)] }
    )
  end

  test 'a save that leaves every document as it stood is no version' do
    metas = @metas + [Meta.new(meta_id: 602, acc_id: 6, kind: 'run', saved_at: at('06-10 09:00:00'))]

    states = DRA::StagingClient.states(groups: @groups, members: @members, metas:)

    assert_not_includes states.map(&:first), at('06-10 09:00:00')
  end
end
