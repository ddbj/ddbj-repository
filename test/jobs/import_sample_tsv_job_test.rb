require 'test_helper'

class ImportSampleTSVJobTest < ActiveJob::TestCase
  setup do
    @submission = submissions(:biosample)
    samples(:first).update!(sample_name: 'sample-A', accession: 'SAMD00099991', status: 'curating')

    @submission.append_update!(
      {'samples' => [{'alias' => 'sample-A', 'attributes' => [{'name' => 'organism', 'value' => 'Homo sapiens'}]}]},
      actor: 'test-seed'
    )

    @import = @submission.sample_tsv_imports.create!(
      actor:      'alice',
      started_at: Time.current
    )
  end

  test 'happy path stamps progress + a SubmissionUpdate' do
    tsv = "sample_name\torganism\nsample-A\tMus musculus\n"

    assert_difference '@submission.updates.count', 1 do
      ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: tsv)
    end

    @import.reload
    assert_equal 'completed',  @import.status
    assert_equal 1,            @import.total
    assert_equal 1,            @import.processed
    assert_equal 0,            @import.failed
    assert_nil   @import.error_report
    assert_not_nil @import.finished_at
  end

  test 'partial failure records error_report but still completes' do
    tsv = "sample_name\torganism\nsample-A\tMus musculus\nunknown-X\tlost\n"

    ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: tsv)

    @import.reload
    assert_equal 'completed', @import.status
    assert_equal 2,           @import.total
    assert_equal 1,           @import.processed
    assert_equal 1,           @import.failed
    assert_match 'unknown',   @import.error_report
  end

  # An import that never got past the header wrote nothing, and recording
  # it as completed made the result screen say "Finished — every row
  # applied" over 0 of 0 rows. The reason was only reachable behind the
  # error-report download.
  test 'a file the importer cannot read at all is recorded as failed' do
    tsv = "name\torganism\nsample-A\tMus musculus\n"

    ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: tsv)

    @import.reload
    assert_equal 'failed', @import.status
    assert_equal :failed,  @import.outcome
    assert_match 'sample_name', @import.error_report
  end

  test 'concurrency guard refuses a second running import on the same submission' do
    chain_before = @submission.updates.count

    holding_advisory_lock "import_sample_tsv:submission:#{@submission.id}" do
      ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: "sample_name\norganism\nsample-A\tMus musculus\n")
    end

    @import.reload
    assert_equal 'failed', @import.status
    assert_match(/already running/, @import.error_report)
    assert_equal chain_before, @submission.updates.count, 'guard must skip append_update!'
  end

  # Left by an import stopped with its process: nothing holds the lock, so
  # it is not running, and it must not refuse this one.
  test 'an import left running by a stopped one is ended, and this one runs' do
    stopped = @submission.sample_tsv_imports.create!(actor: 'someone-else', status: 'running', started_at: 1.hour.ago)

    ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: "sample_name\torganism\n")

    assert_equal 'failed', stopped.reload.status
    assert_equal SampleTSVImport::STOPPED_MESSAGE, stopped.error_report
    assert_not_equal SampleTSVImport::CONFLICT_MESSAGE, @import.reload.error_report
  end

  # Another run of this import holds it, and may yet die: wait, rather
  # than end — and not as a failure, which `discard_on StandardError`
  # would make of it if it met the error first.
  test 'a run that finds the import held waits for it' do
    holding_advisory_lock "import_sample_tsv:#{@import.id}" do
      assert_enqueued_with job: ImportSampleTSVJob do
        ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: "sample_name\torganism\n")
      end
    end

    assert @import.reload.queued_status?
  end

  # Waiting for its job is not stopped: it runs after this one.
  test 'an import still waiting for its job is left waiting' do
    waiting = @submission.sample_tsv_imports.create!(actor: 'someone-else', started_at: Time.current)

    ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: "sample_name\torganism\n")

    assert waiting.reload.queued_status?
  end
end
