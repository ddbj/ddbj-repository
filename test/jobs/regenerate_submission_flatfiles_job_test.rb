require 'test_helper'

class RegenerateSubmissionFlatfilesJobTest < ActiveSupport::TestCase
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
    @admin      = users(:alice).tap { it.update!(admin: true) }
  end

  test 'does nothing when flatfiles would be identical' do
    original_locus_dates = @submission.accessions.pluck(:id, :locus_date).to_h
    original_na_blob_id  = @submission.flatfile_na.blob.id

    progress = RegenerateFlatfilesProgress.create!(total: 1)

    assert_no_difference 'AccessionHistory.count' do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, progress, Date.new(2099, 1, 1)
    end

    @submission.reload

    assert_equal original_na_blob_id, @submission.flatfile_na.blob.id

    @submission.accessions.each do |acc|
      assert_equal original_locus_dates[acc.id], acc.locus_date
    end

    assert_equal 1, progress.reload.processed
  end

  test 'regenerates flatfiles with new locus date when content changed' do
    @submission.flatfile_na.purge
    @submission.flatfile_aa.purge if @submission.flatfile_aa.attached?

    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, progress, Date.new(2026, 7, 1)

    @submission.reload

    assert @submission.flatfile_na.attached?
    assert_match /01-JUL-2026/, @submission.flatfile_na.download

    @submission.accessions.each do |acc|
      assert_equal Date.new(2026, 7, 1), acc.locus_date
    end
  end

  test 'records accession history when content changed' do
    @submission.flatfile_na.purge
    @submission.flatfile_aa.purge if @submission.flatfile_aa.attached?

    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, progress, Date.new(2026, 7, 1)

    histories = AccessionHistory.where(accession: @submission.accessions, action: 'regenerate')

    assert_equal @submission.accessions.count, histories.count
    assert histories.all? { it.user == @admin }
  end

  test 'increments progress' do
    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, progress, Date.new(2026, 7, 1)

    assert_equal 1, progress.reload.processed
  end
end
