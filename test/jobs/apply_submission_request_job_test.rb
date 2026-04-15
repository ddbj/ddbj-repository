require 'test_helper'

class ApplySubmissionRequestJobTest < ActiveSupport::TestCase
  test 'generates NA flatfile for genomic DNA entries' do
    request = SubmissionRequest.new(user: users(:alice))

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    ApplySubmissionRequestJob.perform_now(request)

    submission = request.reload.submission

    assert submission.ddbj_record.attached?
    assert submission.flatfile_na.attached?
    assert_not submission.flatfile_aa.attached?

    histories = AccessionHistory.where(accession: submission.accessions)

    assert_equal submission.accessions.count, histories.count
    assert histories.all? { it.action == 'create' && it.user == request.user }
  end
end
