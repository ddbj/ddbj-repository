require 'application_system_test_case'

# The three ways an import can end, told apart in the first sentence.
# "1,824 applied / 18 failed" is a pair of numbers a curator cannot act
# on: it does not answer the only question they have, which is whether
# their submission is now half-changed.
class SampleTSVImportSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:biosample)
    samples(:first).update!(sample_name: 'sample-A')
  end

  def import(status:, **attrs)
    @submission.sample_tsv_imports.create!(
      actor: 'bob', started_at: 2.minutes.ago, finished_at: Time.current, status:, **attrs
    )
  end

  test 'a clean import says every row landed' do
    record = import(status: 'completed', total: 3, processed: 3, failed: 0)

    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text 'Finished — every row applied'
    assert_no_text 'rejected'
  end

  # The sentence that matters: the rest of the file is already live, so
  # the curator fixes the rejects rather than re-doing the whole thing.
  test 'a partial import says the applied rows are live, and names each rejection' do
    record = import(
      status: 'completed', total: 3, processed: 1, failed: 2,
      error_report: "sample_name\terror\n",
      rejections: [
        {'line' => 2, 'sample_name' => 'sample-A',   'column' => 'status',      'reason' => '"bogus" is not a known status'},
        {'line' => 5, 'sample_name' => 'sample-ZZZ', 'column' => 'sample_name', 'reason' => 'No sample with this name in the submission'}
      ]
    )

    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text 'Finished with 2 rejected rows'
    assert_text 'Applied rows are already live'

    # Row, column and reason on screen — most of these are one typo, and
    # a download to discover that is a round trip the screen need not
    # impose.
    within 'table' do
      assert_text '5'
      assert_text 'sample-ZZZ'
      assert_text 'sample_name'
      assert_text 'No sample with this name in the submission'
    end

    assert_link   'Download error report TSV'
    assert_button 'Upload a corrected file'
  end

  # The opposite reading, and the one that would be dangerous to get
  # wrong: valid rows go in as a single transaction, so a failure leaves
  # nothing behind.
  test 'a failed import says nothing was applied' do
    record = import(status: 'failed', total: 3, processed: 0, failed: 0,
                    error_report: "#{SampleTSVImport::ABORT_PREFIX}PG::ProgramLimitExceeded: row is too big")

    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text 'Import failed — nothing was applied'
    assert_text 'no half-applied state to clean up'
    assert_text 'PG::ProgramLimitExceeded'
    assert_button 'Upload a corrected file'
  end

  # Mission Control is a developer surface, so the screen hands over the
  # lines a curator would be asked to quote instead of sending them
  # there. It also does not offer to "view the job" for a crash they can
  # do nothing with.
  test 'a failed import offers the details to copy rather than a trip to Jobs' do
    record = import(status: 'failed', total: 3, processed: 0, failed: 0,
                    error_report: "#{SampleTSVImport::ABORT_PREFIX}PG::ProgramLimitExceeded: row is too big")

    visit admin_submission_sample_tsv_import_path(@submission, record)

    # Scoped to the page: Tools > Jobs stays in the nav, because that is
    # where a developer goes deliberately.
    within 'main' do
      assert_button  'Copy error details'
      assert_no_link 'View the job'
      assert_no_link 'Jobs'
    end
  end

  # Only said when it is true. A crash is reported to Sentry by the job;
  # a file the importer simply could not read is the curator's to fix,
  # and telling them developers are on it would be a lie that stops them
  # fixing it.
  test 'a crash says developers know, and a bad file does not' do
    crash = import(status: 'failed', total: 0, processed: 0, failed: 0,
                   error_report: "#{SampleTSVImport::ABORT_PREFIX}PG::ProgramLimitExceeded: row is too big")

    visit admin_submission_sample_tsv_import_path(@submission, crash)
    assert_text 'Developers were notified automatically'

    unreadable = import(status: 'failed', total: 0, processed: 0, failed: 0,
                        error_report: 'TSV is missing the required `sample_name` column.')

    visit admin_submission_sample_tsv_import_path(@submission, unreadable)
    assert_text    'Fix the file and upload it again.'
    assert_no_text 'Developers were notified'
  end

  # A third reading, and the one the two-way split got wrong: the file
  # is fine, the curator's move is to wait, and "fix the file and upload
  # it again" sends them to look for a fault that is not there.
  test 'a conflicting import does not blame the file' do
    record = import(status: 'failed', total: 0, processed: 0, failed: 0,
                    error_report: SampleTSVImport::CONFLICT_MESSAGE)

    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text    'Nothing is wrong with the file'
    assert_no_text 'Fix the file'
    assert_no_text 'Developers were notified'
  end

  # Checking counts rows because it can. Applying does not, because the
  # write is one transaction — and splitting it to produce a bar would
  # cost the chain entry that carries the whole intent.
  test 'the progress names both phases and only counts the one it can' do
    record = import(status: 'running', finished_at: nil, phase: 'checking',
                    total: 1842, processed: 1204, failed: 18)

    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text '1,842 rows in the file'
    assert_text '1 · Checking'
    assert_text '1,204 checked'
    assert_text '18 rejected'
    assert_text '2 · Applying'

    record.update!(phase: 'applying', processed: 1824)
    visit admin_submission_sample_tsv_import_path(@submission, record)

    assert_text '1,824 rows, one write'
    assert_text 'it either lands whole or not at all'
  end
end
