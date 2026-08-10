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
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1)
    end

    run.reload

    assert_equal 1, run.failed
    assert_predicate run, :completed?
    assert_not_nil   run.finished_at

    # The reason is on the row, so the screen can show it without
    # sending anyone to the job queue.
    failure = run.failures.sole

    assert_equal @submission,                        failure.submission
    assert_equal @submission.entries.first.accession, failure.label
    assert_match(/not yet implemented for v3/,        failure.message)
  end

  # A date is a change like any other. It used to be applied only to
  # submissions the comparison had already called changed — which the
  # date itself could not make them — so asking for one and nothing else
  # rewrote nothing.
  test 'a new date is a change, and reaches the file that had no other' do
    run = new_run

    assert_difference 'EntryHistory.where(action: "regenerate").count', @submission.entries.count do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1)
    end

    assert_equal 1, run.reload.regenerated

    @submission.entries.each do |acc|
      assert_equal Date.new(2026, 7, 1), acc.reload.locus_date
    end

    assert_match /01-JUL-2026/, @submission.reload.flatfile_na.download
  end

  # Naming accessions is naming whose dates move. The rest of the
  # submission is in the same file and is rewritten with it, but keeps
  # the date it had — so one file can carry two.
  test 'only the named accessions take the new date' do
    named, untouched = @submission.entries.order(:id).first(2)
    before           = untouched.locus_date

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, Date.new(2026, 7, 1),
                                                accessions: [named.accession]

    assert_equal Date.new(2026, 7, 1), named.reload.locus_date
    assert_equal before,               untouched.reload.locus_date

    # Both entries are still in the file the run rewrote — the list
    # chooses dates, not what gets written.
    flatfile = @submission.reload.flatfile_na.download

    assert_includes flatfile, named.accession
    assert_includes flatfile, untouched.accession
  end

  test 'does nothing when flatfiles would be identical' do
    original_locus_dates = @submission.entries.pluck(:id, :locus_date).to_h
    original_na_blob_id  = @submission.flatfile_na.blob.id

    run = new_run

    # The date they already have: asked for, and still nothing to do.
    assert_no_difference 'EntryHistory.count' do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, @submission.entries.first.locus_date
    end

    @submission.reload

    assert_equal original_na_blob_id, @submission.flatfile_na.blob.id

    @submission.entries.each do |acc|
      assert_equal original_locus_dates[acc.id], acc.locus_date
    end

    # Skipped, not regenerated. The distinction is the whole reading of a
    # run that found nothing to do.
    run.reload

    assert_equal 1, run.skipped
    assert_equal 0, run.regenerated
  end

  # The comparison is against what is attached, so a file that is not
  # there is a difference like any other — and the one the tool is
  # reached for when a flatfile has gone missing rather than stale.
  test 'a missing flatfile is a change' do
    @submission.flatfile_na.purge
    @submission.flatfile_aa.purge if @submission.flatfile_aa.attached?

    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, nil

    assert_equal 1, run.reload.regenerated
    assert @submission.reload.flatfile_na.attached?
  end

  # 列と record が食い違ったまま日付を指定せずに走らせると、列の日付が公開されて
  # しまう。2026-08-10、これで PATENT-386 の 5 件を直す regenerate が兄弟 62
  # entry の LOCUS 日付を apply 日へ 4〜10 日巻き戻した。**コメントではなく、
  # 走らせたら止まることで防ぐ。**
  test 'refuses to regenerate while the column and the record disagree about the date' do
    @submission.entries.update_all(locus_date: Date.new(2026, 8, 13))

    before = @submission.flatfile_na.download

    assert_raises RegenerateSubmissionFlatfilesJob::LocusDateDisagreement do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, nil
    end

    assert_equal before, @submission.reload.flatfile_na.download,
                 'the flatfile was rewritten despite the refusal'
  end

  # 日付を入れる entry については列が正なので、食い違っていても進む。名指しの
  # redate もこの経路を通る。
  test 'a date settles the disagreement for the entries it is written to' do
    kept, redated = @submission.entries.order(:accession).to_a

    @submission.entries.update_all(locus_date: Date.new(2026, 8, 13))

    # 名指ししなかった kept は依然として食い違っているので、まだ止まる。
    assert_raises RegenerateSubmissionFlatfilesJob::LocusDateDisagreement do
      RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, Date.new(2026, 9, 1), accessions: [redated.accession]
    end

    # 両方に日付を入れれば通り、両方がその日付で印字される。
    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, Date.new(2026, 9, 1),
                                                accessions: [kept.accession, redated.accession]

    assert_match(/01-SEP-2026/, @submission.reload.flatfile_na.download)

    # 一度通れば record と列が揃うので、以後は日付なしの run でも止まらない。
    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, nil

    assert_match(/01-SEP-2026/, @submission.reload.flatfile_na.download)
  end

  test 'the history names the user who asked for the run' do
    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, Date.new(2026, 7, 1)

    histories = EntryHistory.where(entry: @submission.entries, action: 'regenerate')

    assert_equal @submission.entries.count, histories.count
    assert histories.all? { it.user == @admin }
  end

  # A submission destroyed between enqueue and execution makes reading
  # the job's own arguments the thing that fails. Reaching for them from
  # inside the handler raised the same error again, so nothing was
  # recorded and the run could never reach its total — it sat at
  # "Regenerating…" until the stale bound caught it an hour later.
  test 'a submission destroyed before the job ran is still counted, and named' do
    run        = new_run
    serialized = RegenerateSubmissionFlatfilesJob.new(@submission, @admin, run, Date.new(2026, 7, 1)).serialize
    id         = @submission.id

    @submission.destroy!

    assert_raises ActiveJob::DeserializationError do
      ActiveJob::Base.deserialize(serialized).perform_now
    end

    run.reload

    assert_equal 1, run.failed
    assert_not_nil  run.finished_at

    failure = run.failures.sole

    assert_nil     failure.submission
    assert_equal   "Submission ##{id} (deleted)", failure.label
    assert_match(/DeserializationError/,          failure.message)
  end

  test 'counts what it did, and closes the run when the last job lands' do
    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, Date.new(2026, 7, 1)

    run.reload

    assert_equal 1, run.regenerated
    assert_predicate run, :completed?
    assert_not_nil   run.finished_at
  end

  # Withdrawing an entry is for keeping it out of what goes out. The
  # record is the account of what was submitted and keeps it.
  test 'a retracted entry leaves the flatfile and stays in the record' do
    kept, gone = @submission.entries.order(:id).first(2)

    before = @submission.flatfile_na.download

    assert_includes before, kept.accession
    assert_includes before, gone.accession

    gone.update!(status: :withdrawn)

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, new_run, nil

    after = @submission.reload.flatfile_na.download

    assert_includes after, kept.accession
    assert_not_includes after, gone.accession

    record = Oj.load(@submission.ddbj_record.download, mode: :strict)
    ids    = record.dig('sequences', 'entries').map { it['id'] }

    assert_includes ids, gone.entry_id, 'the record is what was submitted, not what went out'
  end

  # `changed?` decides whether to rewrite anything at all, so a status
  # change that it cannot see is a status change that never reaches the
  # flatfile.
  test 'retracting an entry is a change worth regenerating for' do
    run = new_run

    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, nil

    assert_equal 1, run.reload.skipped, 'nothing changed, so nothing was rewritten'

    @submission.entries.order(:id).first.update!(status: :canceled)

    run = new_run
    RegenerateSubmissionFlatfilesJob.perform_now @submission, @admin, run, nil

    assert_equal 1, run.reload.regenerated
  end

  private

  def new_run
    RegenerateFlatfilesRun.create!(actor: 'admin:alice', target: 'accessions', total: 1, started_at: Time.current)
  end
end
