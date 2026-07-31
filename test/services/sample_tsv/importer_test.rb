require 'test_helper'

class SampleTSV::ImporterTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:biosample)
    @sample     = samples(:first).tap { it.update!(sample_name: 'sample-A', accession: 'SAMD00099991', status: 'curating') }

    @submission.append_update!({
      'samples' => [
        {'alias' => 'sample-A', 'attributes' => [
          {'name' => 'collection_date', 'value' => '2026-03-01'},
          {'name' => 'organism',        'value' => 'Homo sapiens'},
          {'name' => 'sample_title',    'value' => 'A title'}
        ]}
      ]
    }, actor: 'test-seed')
  end

  def run_importer(tsv)
    SampleTSV::Importer.new(submission: @submission, tsv_body: tsv, actor: 'admin:bob').call
  end

  test 'applies a row that touches typed cols + edits attributes via single SubmissionUpdate' do
    tsv = <<~TSV
      sample_name\tstatus\tcollection_date\torganism\tsample_title
      sample-A\taccession_issued\t2026-04-15\tMus musculus\tA new title
    TSV

    chain_before = @submission.updates.count
    result       = run_importer(tsv)

    assert_equal 1, result.total
    assert_equal 1, result.processed
    assert_equal 0, result.failed
    assert_equal chain_before + 1, @submission.updates.count, 'exactly one SubmissionUpdate per TSV import'
    assert_equal 'tsv_import',     @submission.updates.last.source

    v3_sample = @submission.reload.materialised_record['samples'].first
    attrs     = v3_sample['attributes'].to_h {|a| [a['name'], a['value']] }
    assert_equal 'Mus musculus', attrs['organism']
    assert_equal '2026-04-15',   attrs['collection_date']
    assert_equal 'A new title',  attrs['sample_title']

    # Typed lifts in v3 follow the bag.
    assert_equal 'A new title',                                   v3_sample['title']
    assert_equal({'name' => 'Mus musculus'},                      v3_sample['organism'])

    @sample.reload
    assert_equal 'accession_issued', @sample.status
    assert_equal 'Mus musculus',     @sample.organism
    assert_equal 'A new title',      @sample.title
  end

  test 'blank attribute cell DELETES the attribute (B(ii) semantics)' do
    tsv = <<~TSV
      sample_name\tcollection_date\torganism\tsample_title
      sample-A\t\tHomo sapiens\tA title
    TSV

    result = run_importer(tsv)
    assert_equal 1, result.processed

    attrs = @submission.reload.materialised_record['samples'].first['attributes'].to_h {|a| [a['name'], a['value']] }
    assert_not attrs.key?('collection_date'), 'blank cell must remove the attribute'
    assert_equal 'Homo sapiens', attrs['organism']
  end

  test 'unknown column header is added as a new attribute (C: yes)' do
    tsv = <<~TSV
      sample_name\tnovel_attr
      sample-A\tnew-value
    TSV

    result = run_importer(tsv)
    assert_equal 1, result.processed

    attrs = @submission.reload.materialised_record['samples'].first['attributes'].to_h {|a| [a['name'], a['value']] }
    assert_equal 'new-value', attrs['novel_attr']
  end

  test 'unknown sample_name lands in error_report without polluting other rows' do
    tsv = <<~TSV
      sample_name\torganism
      sample-A\tHomo sapiens
      sample-ZZZ\tunknown
    TSV

    result = run_importer(tsv)
    assert_equal 2, result.total
    assert_equal 1, result.processed
    assert_equal 1, result.failed
    assert_match 'unknown sample_name', result.error_report
    assert_match 'sample-ZZZ',          result.error_report
  end

  test 'unknown status fails the row' do
    tsv = <<~TSV
      sample_name\tstatus
      sample-A\tbogus_status
    TSV

    result = run_importer(tsv)
    assert_equal 0, result.processed
    assert_equal 1, result.failed
    assert_match 'unknown status', result.error_report
  end

  # A spreadsheet downloaded before assignment moved to the request still
  # carries an `assignee_uid` column. An unrecognised header is read as a
  # v3 attribute name, so merely dropping the column from the format would
  # have turned every re-upload of an old export into a record with a
  # bogus attribute on every sample — committed to the chain, by way of
  # the documented download-edit-upload loop.
  test 'a column this format used to emit is ignored, not read as an attribute' do
    result = run_importer(<<~TSV)
      sample_name\tassignee_uid\torganism
      sample-A\tbob\tMus musculus
    TSV

    assert_equal 1, result.processed

    attrs = @submission.reload.materialised_record['samples'].first['attributes'].to_h { [it['name'], it['value']] }

    assert_equal 'Mus musculus', attrs['organism']
    assert_not attrs.key?('assignee_uid'), 'a retired column must not become sample data'
  end

  # Fix the file and upload it again is the documented loop, and the
  # error report is the file. Its `error` column is an unrecognised
  # header, so without stripping it the stale reason would be written
  # into the record as an attribute of every row it explains.
  test 'the error report can be corrected and re-uploaded without writing the reason into the record' do
    first = run_importer(<<~TSV)
      sample_name	status	organism
      sample-A	bogus	Mus musculus
    TSV

    assert_equal 1, first.failed

    corrected = first.error_report.sub("\tbogus\t", "\tpublic\t")
    result    = run_importer(corrected)

    assert_equal 1, result.processed

    attrs = @submission.reload.materialised_record['samples']
                       .find { it['alias'] == 'sample-A' }['attributes']
                       .to_h { [it['name'], it['value']] }

    assert_equal 'Mus musculus', attrs['organism']
    assert_not attrs.key?('error'), 'the rejection reason must not become sample data'
    assert_equal 'public', @sample.reload.status
  end

  test 'no SubmissionUpdate is created when every row fails' do
    chain_before = @submission.updates.count

    run_importer(<<~TSV)
      sample_name
      unknown-1
      unknown-2
    TSV

    assert_equal chain_before, @submission.updates.count
  end

  test 'fatal_error is set (and processed/total = 0) when sample_name column is missing' do
    tsv = "organism\nHomo sapiens\n"

    result = run_importer(tsv)

    assert_equal 0, result.total
    assert_equal 0, result.processed
    assert_match(/sample_name/, result.fatal_error)
  end

  test 'strips UTF-8 BOM from the leading header so Excel-exported TSVs parse' do
    tsv = "\u{FEFF}sample_name\torganism\nsample-A\tMus musculus\n"

    result = run_importer(tsv)

    assert_equal 1, result.processed
    assert_nil   result.fatal_error
  end
end
