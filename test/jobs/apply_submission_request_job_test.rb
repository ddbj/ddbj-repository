require 'test_helper'

class ApplySubmissionRequestJobTest < ActiveSupport::TestCase
  test 'generates NA flatfile for genomic DNA entries' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert submission.ddbj_record.attached?
    assert submission.flatfile_na.attached?
    assert_not submission.flatfile_aa.attached?

    histories = EntryHistory.where(entry: submission.entries)

    assert_equal submission.entries.count, histories.count
    assert histories.all? { it.action == 'create' && it.user == request.user }
  end

  # SystemStackError は StandardError ではないので、rescue を取り違えると
  # request が applying のまま取り残され、クライアントが status を永久に
  # ポーリングし続ける。終端状態 (application_failed) に落ちることを保証する。
  test 'marks the request as application_failed even on a non-StandardError' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    boom = ->(*) { raise SystemStackError, 'stack level too deep' }

    assert_raises SystemStackError do
      DDBJRecord::StreamingParser.stub :new, boom do
        ApplySubmissionRequestJob.perform_now request
      end
    end

    request.reload

    assert request.application_failed?
    assert_equal 'TRD_R9999', request.error_code
    assert_equal 'stack level too deep', request.error_message
    assert_not request.processing?
  end

  # 採番が尽きたことは、クライアントがランを打ち切るかどうかの判断に使う。
  # 文言ではなくコードで分岐できるようにしておく。
  test 'records TRD_R0012 when the accession numbers run out' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update!(
      prefix: Sequence.config.fetch(:jpo_na).last[:prefix],
      next:   1000000
    )

    ApplySubmissionRequestJob.perform_now request

    request.reload

    assert request.application_failed?
    assert_equal 'TRD_R0012', request.error_code
    assert_match(/no numbers left/, request.error_message)

    # 尽きたときは 1 件も消費しないので、prefix を足せばそのまま適用できる。
    assert_nil request.submission
  end

  # 前回の失敗の痕跡が残っていると、成功しているのに「今まさに失敗している」と読まれる。
  test 'clears the previous failure before applying' do
    request = SubmissionRequest.new(
      user:          users(:alice),
      db:            'st26',
      error_code:    'TRD_R0012',
      error_message: 'jpo_na: no numbers left after QX (wanted 3 more)'
    )

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    ApplySubmissionRequestJob.perform_now request

    request.reload

    assert request.applied?
    assert_nil request.error_code
    assert_nil request.error_message
  end

  test 'refuses v3 records, transitions request to application_failed cleanly' do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/v3_trad_gnm.json').open,
      filename:     'v3_trad_gnm.json',
      content_type: 'application/json'
    )

    request.save!

    # V3NotImplementedError is a StandardError so the job's bareword
    # rescue catches it; request transitions to :application_failed
    # with the deferral message recorded for operator triage.
    ApplySubmissionRequestJob.perform_now request

    request.reload
    assert request.application_failed?
    assert_match(/v3 record application not yet implemented/, request.error_message)
  end
end
