require 'test_helper'

class RegenerateSubmissionFlatfilesJobTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:one)
    @admin      = users(:alice).tap { it.update!(admin: true) }

    @submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    @submission.accessions.update_all locus_date: Date.new(2026, 7, 1)
  end

  test 'regenerates flatfiles with new locus date' do
    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now(@submission, @admin, progress)

    @submission.reload

    assert @submission.flatfile_na.attached?

    flatfile = @submission.flatfile_na.download

    assert_match /01-JUL-2026/, flatfile
  end

  test 'records accession history' do
    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now(@submission, @admin, progress)

    histories = AccessionHistory.where(accession: @submission.accessions, action: 'regenerate')

    assert_equal @submission.accessions.count, histories.count
    assert histories.all? { it.user == @admin }
  end

  test 'increments progress' do
    progress = RegenerateFlatfilesProgress.create!(total: 1)

    RegenerateSubmissionFlatfilesJob.perform_now(@submission, @admin, progress)

    progress.reload

    assert_equal 1, progress.processed
  end
end
