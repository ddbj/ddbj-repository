require 'test_helper'

class RegenerateSubmissionFlatfilesJobTest < ActiveSupport::TestCase
  setup do
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')

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

  test 'refuses v3 submissions, and writes down which one and why' do
    run = new_run
    @submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/v3_trad_gnm.json').open,
      filename:     'v3_trad_gnm.json',
      content_type: 'application/json'
    )

    # V3NotImplementedError is a StandardError so rescue_from catches it
    # AND re-raises: the queue still records a failed job, and the run
    # still reaches a result instead of hanging at loading?.
    assert_raises DDBJRecord::V3NotImplementedError do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1), force: true
    end

    run.reload

    assert_equal 1, run.failed
    assert_predicate run, :completed?
    assert_not_nil   run.finished_at

    # The reason is on the row, so the screen can show it without
    # sending anyone to the job queue.
    failure = run.failures.sole

    assert_equal @submission,                        failure.submission
    assert_equal @submission.accessions.first.number, failure.label
    assert_match(/not yet implemented for v3/,        failure.message)
  end

  test 'force: true regenerates even when flatfiles would be identical' do
    run = new_run

    assert_difference 'AccessionHistory.where(action: "regenerate").count', @submission.accessions.count do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1), force: true
    end

    @submission.accessions.each do |acc|
      assert_equal Date.new(2026, 7, 1), acc.reload.locus_date
    end
  end

  test 'does nothing when flatfiles would be identical' do
    original_locus_dates = @submission.accessions.pluck(:id, :locus_date).to_h
    original_na_blob_id  = @submission.flatfile_na.blob.id

    run = new_run

    assert_no_difference 'AccessionHistory.count' do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2099, 1, 1)
    end

    @submission.reload

    assert_equal original_na_blob_id, @submission.flatfile_na.blob.id

    @submission.accessions.each do |acc|
      assert_equal original_locus_dates[acc.id], acc.locus_date
    end

    # Skipped, not regenerated. The distinction is the whole reading of a
    # run made with the rewrite option off.
    run.reload

    assert_equal 1, run.skipped
    assert_equal 0, run.regenerated
  end

  test 'regenerates flatfiles with new locus date when content changed' do
    @submission.flatfile_na.purge
    @submission.flatfile_aa.purge if @submission.flatfile_aa.attached?

    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1)

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

    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1)

    histories = AccessionHistory.where(accession: @submission.accessions, action: 'regenerate')

    assert_equal @submission.accessions.count, histories.count
    assert histories.all? { it.user == @admin }
  end

  test 'counts what it did, and closes the run when the last job lands' do
    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1), force: true

    run.reload

    assert_equal 1, run.regenerated
    assert_predicate run, :completed?
    assert_not_nil   run.finished_at
  end

  private

  def new_run
    RegenerateFlatfilesRun.create!(actor: 'admin:alice', target: 'accessions', total: 1, started_at: Time.current)
  end
end
