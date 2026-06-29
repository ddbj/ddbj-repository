require 'test_helper'

class ImportSampleTSVJobTest < ActiveSupport::TestCase
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

  test 'concurrency guard refuses a second running import on the same submission' do
    @submission.sample_tsv_imports.create!(
      actor:      'someone-else',
      status:     'running',
      started_at: 30.seconds.ago
    )

    chain_before = @submission.updates.count

    ImportSampleTSVJob.perform_now(import_id: @import.id, tsv_body: "sample_name\norganism\nsample-A\tMus musculus\n")

    @import.reload
    assert_equal 'failed', @import.status
    assert_match(/already running/, @import.error_report)
    assert_equal chain_before, @submission.updates.count, 'guard must skip append_update!'
  end
end
