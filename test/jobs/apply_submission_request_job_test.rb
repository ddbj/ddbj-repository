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

    histories = AccessionHistory.where(accession: submission.accessions)

    assert_equal submission.accessions.count, histories.count
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
    assert_equal 'stack level too deep', request.error_message
    assert_not request.processing?
  end
end
