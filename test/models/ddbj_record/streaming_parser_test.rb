require 'test_helper'

class DDBJRecord::StreamingParserTest < ActiveSupport::TestCase
  def parser_for(fixture)
    DDBJRecord::StreamingParser.new(file_fixture("ddbj_record/#{fixture}"))
  end

  test 'metadata returns a DDBJRecord::Root' do
    meta = parser_for('multi_entry.json').metadata

    assert_kind_of DDBJRecord::Root, meta
  end

  test 'metadata parses submission' do
    meta = parser_for('multi_entry.json').metadata

    assert_kind_of DDBJRecord::Submission, meta.submission
    assert_equal 'PLN', meta.submission.division
    assert_equal 'GNM', meta.submission.trad_submission_category
  end

  test 'metadata parses experiments' do
    meta = parser_for('multi_entry.json').metadata

    assert_equal 1, meta.experiments.size
    assert_kind_of DDBJRecord::Experiment, meta.experiments.first
    assert_equal 'SPAdes v 3.15', meta.experiments.first.experiment_attributes['assembly_method']
  end

  test 'metadata parses common_source' do
    cs = parser_for('multi_entry.json').metadata.sequences.common_source

    assert_kind_of DDBJRecord::Source, cs
    assert_equal 'Testus plantus', cs.organism
    assert_equal 'genomic DNA', cs.mol_type
  end

  test 'metadata returns empty entries and features' do
    meta = parser_for('multi_entry.json').metadata

    assert_equal [], meta.sequences.entries
    assert_equal [], meta.features
  end

  test 'features_by_sequence_id groups features by sequence_id' do
    features = parser_for('multi_entry.json').features_by_sequence_id

    assert_equal %w[TST1ch01 TST1ch02].sort, features.keys.sort
  end

  test 'features_by_sequence_id builds DDBJRecord::Feature objects' do
    features = parser_for('multi_entry.json').features_by_sequence_id
    feat     = features['TST1ch01'].first

    assert_kind_of DDBJRecord::Feature, feat
    assert_equal 'assembly_gap', feat.type
    assert_equal '20..30', feat.location
  end

  test 'features_by_sequence_id builds nested Qualifier objects' do
    features = parser_for('multi_entry.json').features_by_sequence_id
    qual     = features['TST1ch01'].first.qualifiers['estimated_length'].first

    assert_kind_of DDBJRecord::Qualifier, qual
    assert_equal 'known', qual.value
  end

  test 'each_entry yields DDBJRecord::Entry objects' do
    entries = parser_for('multi_entry.json').each_entry.to_a

    entries.each do |entry|
      assert_kind_of DDBJRecord::Entry, entry
    end
  end

  test 'each_entry yields entries in order' do
    ids = parser_for('multi_entry.json').each_entry.map(&:id)

    assert_equal %w[TST1ch01 TST1ch02 TST1u001], ids
  end

  test 'each_entry preserves entry fields' do
    entry = parser_for('multi_entry.json').each_entry.first

    assert_equal 'TST1ch01', entry.name
    assert_equal 'linear',   entry.topology
    assert_equal 12345,      entry.tax_id
    assert_equal 'atgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgc', entry.sequence
  end

  test 'each_entry builds nested source_features' do
    entry = parser_for('multi_entry.json').each_entry.first
    sf    = entry.source_features.first

    assert_kind_of DDBJRecord::SourceFeature, sf
    assert_equal '1..E', sf.location
    assert_equal ['@@[organism]@@ @@[cultivar]@@ DNA, chromosome @@[chromosome]@@'], sf.definition
  end

  test 'each_entry returns an enumerator without a block' do
    parser = parser_for('multi_entry.json')

    assert_kind_of Enumerator, parser.each_entry
    assert_equal 3, parser.each_entry.count
  end

  test 'parses metadata from example.json' do
    assert_equal 'PAT', parser_for('example.json').metadata.submission.division
  end

  test 'parses st26 section that appears after features' do
    st26 = parser_for('example.json').metadata.st26

    assert_kind_of DDBJRecord::St26, st26
    assert_equal 'Test Corp',            st26.applicant_names.first.text
    assert_equal 'Test Inventor',        st26.inventor_names.first.text
    assert_equal 'Test Invention Title', st26.invention_titles.first.text
  end

  test 'streams entries with nested source objects' do
    entry = parser_for('example.json').each_entry.first
    sf    = entry.source_features.first

    assert_kind_of DDBJRecord::Source, sf.source
    assert_equal 'Homo sapiens', sf.source.organism
    assert_equal 'genomic DNA', sf.source.mol_type
  end

  test 'yields the same entries as DDBJRecord.parse' do
    full = File.open(file_fixture('ddbj_record/example.json')) { DDBJRecord.parse(it) }

    parser_for('example.json').each_entry.zip(full.sequences.entries).each do |streamed, expected|
      assert_equal expected, streamed
    end
  end

  test 'handles indent: 2 formatting from Writer-generated output' do
    original = File.open(file_fixture('ddbj_record/example.json')) { DDBJRecord.parse(it) }
    file     = DDBJRecord.generate(original)

    begin
      parser  = DDBJRecord::StreamingParser.new(file.path)
      entries = parser.each_entry.to_a

      assert_equal 2, entries.size
      assert_equal original.sequences.entries.map(&:id), entries.map(&:id)
      assert_equal original.sequences.entries.map(&:sequence), entries.map(&:sequence)
    ensure
      file.close!
    end
  end

  test 'does not confuse nested "entries" with sequences.entries' do
    json = JSON.generate(
      schema_version: 'v2',

      provenance: {
        source_format: 'test',
        entries:       [1, 2, 3]
      },

      submission: {
        submitters: [],
        db_xrefs:   [],
        references: [],
        comments:   [],
        division:   'PAT'
      },

      sequences: {
        common_source: {
          organism:   '',
          mol_type:   '',
          qualifiers: {}
        },

        entries: [
          id:              'e1',
          type:            'other',
          topology:        'linear',
          sequence:        'atgc',
          source_features: []
        ]
      },

      features: []
    )

    file = Tempfile.open(['nested_entries', '.json'])

    begin
      file.write json
      file.rewind

      parser  = DDBJRecord::StreamingParser.new(file.path)
      entries = parser.each_entry.to_a

      assert_equal 1, entries.size
      assert_equal 'e1', entries.first.id
      assert_equal({'entries' => [1, 2, 3]}, parser.metadata.provenance.extras)
    ensure
      file.close!
    end
  end

  test 'falls back to DDBJRecord.parse and yields entries correctly for minified JSON' do
    original = File.open(file_fixture('ddbj_record/example.json')) { DDBJRecord.parse(it) }
    file     = Tempfile.open(['minified', '.json'])

    begin
      file.write JSON.generate(Oj.load(file_fixture('ddbj_record/example.json').read))
      file.rewind

      parser  = DDBJRecord::StreamingParser.new(file.path)
      entries = parser.each_entry.to_a

      assert_equal 2, entries.size
      assert_equal original.sequences.entries.map(&:id), entries.map(&:id)
      assert_equal original.sequences.entries.map(&:sequence), entries.map(&:sequence)
    ensure
      file.close!
    end
  end

  test 'extracts metadata from minified JSON' do
    file = Tempfile.open(['minified', '.json'])

    begin
      file.write JSON.generate(Oj.load(file_fixture('ddbj_record/multi_entry.json').read))
      file.rewind

      parser = DDBJRecord::StreamingParser.new(file.path)

      assert_equal 'PLN', parser.metadata.submission.division
      assert_equal 3, parser.each_entry.count
    ensure
      file.close!
    end
  end
end
