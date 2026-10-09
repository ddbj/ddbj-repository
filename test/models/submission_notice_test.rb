require 'test_helper'

class SubmissionNoticeTest < ActiveSupport::TestCase
  test 'posts to the request thread as nobody, naming each accession' do
    submission = submissions(:biosample)
    notice     = SubmissionNotice.accession_issued!(submission, %w[SAMD00000001 SAMD00000002], names: {'SAMD00000001' => 'sample1'})

    assert notice.system_role?
    assert_nil notice.user
    assert_equal submission.request, notice.submission_request

    assert_includes notice.body, 'issued 2 accessions for your BioSample submission'
    assert_includes notice.body, '  - SAMD00000001  sample1'
    assert_includes notice.body, '  - SAMD00000002'
  end

  # A hundred thousand samples are neither a thread message nor a mail.
  test 'a long list gives way to the accessions page' do
    submission = submissions(:biosample)
    accessions = (1..(SubmissionNotice::LIST_LIMIT + 1_200)).map { format('SAMD%08d', it) }
    body       = SubmissionNotice.accession_issued!(submission, accessions).body

    assert_includes body, "issued #{accessions.size.to_fs(:delimited)} accessions"
    assert_includes body, accessions[SubmissionNotice::LIST_LIMIT - 1]
    assert_not_includes body, accessions[SubmissionNotice::LIST_LIMIT]
    assert_includes body, "…and 1,200 more on the accessions page: #{WebApp.url_for("/requests/#{submission.request.id}/accessions")}"
  end

  # The accessions page lists curation rows, and a DRA submission is one.
  test "a DRA submission's rest are in its record, not on the accessions page" do
    request    = submission_requests(:dra)
    accessions = (1..(SubmissionNotice::LIST_LIMIT + 1)).map { format('DRR%06d', it) }
    body       = SubmissionNotice.accession_issued!(request.submission, accessions).body

    assert_includes body, "…and 1 more in the record: #{WebApp.url_for("/requests/#{request.id}")}"
  end

  # A request sent here has no D-way id; the submitter knows it by its own.
  test 'names the submission by the request the submitter knows' do
    request = submission_requests(:bioproject)
    request.submission.update_column :source_id, nil

    assert_includes SubmissionNotice.accession_issued!(request.submission, %w[PRJDB1]).body, "submission (##{request.id})"
  end

  # It asks nothing of the submitter, and answers nothing for the curator.
  test 'is neither unread for the submitter nor an answer to the submitter' do
    request = submission_requests(:biosample)
    asked   = request.messages.create!(user: request.user, author_role: :submitter, body: 'When?')

    SubmissionNotice.accession_issued!(request.submission, %w[SAMD00000001])

    assert_not SubmissionRequest.needs_submitter_action.exists?(request.id)
    assert_equal [asked], request.messages.unanswered.to_a
  end
end
