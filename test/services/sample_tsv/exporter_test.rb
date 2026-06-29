require 'test_helper'

class SampleTSV::ExporterTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:biosample)
    @first      = samples(:first).tap  { it.update!(sample_name: 'sample-A', accession: 'SAMD00099991', status: 'curating') }
    @second     = samples(:second).tap { it.update!(sample_name: 'sample-B', accession: 'SAMD00099992', status: 'public', assignee: users(:bob)) }

    @submission.append_update!({
      'samples' => [
        {'alias' => 'sample-A', 'attributes' => [
          {'name' => 'collection_date', 'value' => '2026-03-01'},
          {'name' => 'organism',        'value' => 'Homo sapiens'},
          {'name' => 'sample_title',    'value' => 'A title'}
        ]},
        {'alias' => 'sample-B', 'attributes' => [
          {'name' => 'geo_loc_name', 'value' => 'Japan'},
          {'name' => 'organism',     'value' => 'Mus musculus'}
        ]}
      ]
    }, actor: 'test')
  end

  test 'emits header with identifier + typed cols + sorted attribute union, then one row per sample' do
    tsv  = SampleTSV::Exporter.new(@submission).each.to_a.join
    rows = tsv.lines.map { it.chomp.split("\t", -1) }

    expected_header = %w[sample_name accession status assignee_uid collection_date geo_loc_name organism sample_title]
    assert_equal expected_header, rows[0]

    # Rows in AR id order (samples :first then :second).
    assert_equal [
      'sample-A',
      'SAMD00099991',
      'curating',
      '',
      '2026-03-01',
      '',
      'Homo sapiens',
      'A title'
    ], rows[1]

    assert_equal [
      'sample-B',
      'SAMD00099992',
      'public',
      'bob',
      '',
      'Japan',
      'Mus musculus',
      ''
    ], rows[2]
  end

  test 'filters reserved column names (status / accession / ...) from the attribute column union' do
    # A v3 attribute that happens to be named like a reserved column
    # would otherwise duplicate that header in the output and discard
    # the value on re-import — the importer would treat the duplicate
    # as a reserved column.
    @submission.append_update!({
      'samples' => [
        {'alias' => 'sample-A', 'attributes' => [
          {'name' => 'status',   'value' => 'should-not-leak'},
          {'name' => 'organism', 'value' => 'Homo sapiens'}
        ]}
      ]
    }, actor: 'test')

    header = SampleTSV::Exporter.new(@submission).each.first.chomp.split("\t", -1)

    assert_equal 1, header.count('status'),       'reserved column `status` must not double-emit'
    assert_equal 1, header.count('accession'),    'reserved column `accession` must not double-emit'
    assert_equal 1, header.count('sample_name'),  'reserved column `sample_name` must not double-emit'
    assert_equal 1, header.count('assignee_uid'), 'reserved column `assignee_uid` must not double-emit'
  end

  test 'sanitises tabs and newlines inside cell values (TSV separator collision)' do
    @submission.append_update!({
      'samples' => [
        {'alias' => 'sample-A', 'attributes' => [{'name' => 'note', 'value' => "line1\nline2\tafter-tab"}]}
      ]
    }, actor: 'test')

    tsv  = SampleTSV::Exporter.new(@submission).each.to_a.join
    rows = tsv.lines.map { it.chomp.split("\t", -1) }

    note_col = rows[0].index('note')
    assert_equal 'line1 line2 after-tab', rows[1][note_col]
  end

  test 'returns header-only output when the submission has no samples' do
    @submission.samples.destroy_all

    tsv = SampleTSV::Exporter.new(@submission).each.to_a.join

    assert_equal 1, tsv.lines.size
    assert tsv.lines.first.chomp.split("\t", -1).first == 'sample_name'
  end
end
