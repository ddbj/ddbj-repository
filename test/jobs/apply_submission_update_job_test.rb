require 'test_helper'

class ApplySubmissionUpdateJobTest < ActiveSupport::TestCase
  setup do
    request = SubmissionRequest.new(user: users(:alice))

    request.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    request.save!

    ApplySubmissionRequestJob.perform_now request

    @submission = request.reload.submission
  end

  test 'regenerates flatfiles' do
    original_na_blob_id = @submission.flatfile_na.blob.id

    json = @submission.ddbj_record.open { JSON.parse(it.read) }
    json['sequences']['entries'][0]['definition'] = 'modified definition'

    update = @submission.updates.new
    update.ddbj_record.attach io: StringIO.new(JSON.generate(json)), filename: 'example.json', content_type: 'application/json'
    update.save!

    ApplySubmissionUpdateJob.perform_now update

    @submission.reload

    assert @submission.flatfile_na.attached?
    assert_not_equal original_na_blob_id, @submission.flatfile_na.blob.id

    history = AccessionHistory.where(accession: @submission.accessions, action: 'update').sole

    assert_equal users(:alice), history.user
  end

  test 'purges flatfile when entries of that type are removed' do
    # Manually attach a flatfile_aa to simulate a prior submission with AA entries
    @submission.flatfile_aa.attach io: StringIO.new('dummy'), filename: 'example-aa.flat', content_type: 'text/plain'
    assert @submission.flatfile_aa.attached?

    json = @submission.ddbj_record.open { JSON.parse(it.read) }
    json['sequences']['entries'][0]['definition'] = 'modified definition'

    update = @submission.updates.new
    update.ddbj_record.attach io: StringIO.new(JSON.generate(json)), filename: 'example.json', content_type: 'application/json'
    update.save!

    ApplySubmissionUpdateJob.perform_now update

    @submission.reload

    assert @submission.flatfile_na.attached?
    assert_not @submission.flatfile_aa.attached?
  end
end
