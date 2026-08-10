require 'test_helper'

class ApplySubmissionRequestJobTest < ActiveSupport::TestCase
  test 'generates NA flatfile for genomic DNA entries' do
    request = build_request('ddbj_record/example.json')

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert submission.ddbj_record.attached?
    assert submission.flatfile_na.attached?
    assert_not submission.flatfile_aa.attached?

    histories = EntryHistory.where(entry: submission.entries)

    assert_equal submission.entries.count, histories.count
    assert histories.all? { it.action == 'create' && it.user == request.user }
  end

  # LOCUS date は公開作業を行う人が決める値で、record に入って届く。列にも
  # flatfile にも同じ日付が入らなければならない: 列に apply 日を入れて
  # flatfile には record の日付を印字していたため、apply した瞬間から両者が
  # 食い違い、後の regenerate が印字済みの日付を apply 日へ引き戻していた。
  test 'takes the LOCUS date from the record, into both the column and the flatfile' do
    request = build_request('ddbj_record/example.json') {|record|
      record['sequences']['entries'].each { it['locus_date'] = '2026-08-13' }
    }

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert_equal ['2026-08-13'], submission.entries.distinct.pluck(:locus_date).map(&:to_s)
    assert_includes submission.flatfile_na.download, '13-AUG-2026'
  end

  # `last_updated` は 2026-08 までのこのフィールドの名前で、既存の record は
  # すべてその名前で書かれている。読めなくなると LOCUS 行の日付が全部空になる。
  test 'still reads the date from a record written under the old name' do
    request = build_request('ddbj_record/example.json') {|record|
      record['sequences']['entries'].each { it['last_updated'] = '2026-08-13' }
    }

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert_equal ['2026-08-13'], submission.entries.distinct.pluck(:locus_date).map(&:to_s)
    assert_includes submission.flatfile_na.download, '13-AUG-2026'
  end

  # to_date (= Date.parse) は推測する。"8/13" は「実行した年」の 8 月 13 日に
  # なり、その値が公開される flatfile の LOCUS 行に印字される。推測より拒否。
  # pass 1 は採番の前なので、ここで落ちても 1 件も消費しない。
  test 'refuses a locus_date that is not written as YYYY-MM-DD' do
    request = build_request('ddbj_record/example.json') {|record|
      record['sequences']['entries'].each { it['locus_date'] = '8/13' }
    }

    ApplySubmissionRequestJob.perform_now request

    request.reload

    assert request.application_failed?
    assert_equal 'TRD_R0014', request.error_code
    assert_match(/not written as YYYY-MM-DD/, request.error_message)
    assert_nil request.submission
  end

  # 日付を言わない record のときだけ apply 日が立つ。
  test 'falls back to the apply date when the record names none' do
    request = build_request('ddbj_record/example.json')

    ApplySubmissionRequestJob.perform_now request

    assert_equal [Date.current], request.reload.submission.entries.distinct.pluck(:locus_date)
  end

  # SystemStackError は StandardError ではないので、rescue を取り違えると
  # request が applying のまま取り残され、クライアントが status を永久に
  # ポーリングし続ける。終端状態 (application_failed) に落ちることを保証する。
  test 'marks the request as application_failed even on a non-StandardError' do
    request = build_request('ddbj_record/example.json')
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
    request = build_request('ddbj_record/example.json')

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
    request = build_request('ddbj_record/example.json')

    request.update!(
      error_code:    'TRD_R0012',
      error_message: 'jpo_na: no numbers left after QX (wanted 3 more)'
    )

    ApplySubmissionRequestJob.perform_now request

    request.reload

    assert request.applied?
    assert_nil request.error_code
    assert_nil request.error_message
  end

  test 'refuses v3 records, transitions request to application_failed cleanly' do
    request = build_request('ddbj_record/v3_trad_gnm.json')

    # V3NotImplementedError is a StandardError so the job's bareword
    # rescue catches it; request transitions to :application_failed
    # with the deferral message recorded for operator triage.
    ApplySubmissionRequestJob.perform_now request

    request.reload
    assert request.application_failed?
    assert_match(/v3 record application not yet implemented/, request.error_message)
  end

  private

  # A request carrying a fixture record, with the parsed JSON handed to the
  # block first so a test can say what it needs the record to contain.
  def build_request(fixture)
    record = JSON.parse(file_fixture(fixture).read)

    yield record if block_given?

    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

    request.ddbj_record.attach(
      io:           StringIO.new(JSON.generate(record)),
      filename:     File.basename(fixture),
      content_type: 'application/json'
    )

    request.save!
    request
  end
end
