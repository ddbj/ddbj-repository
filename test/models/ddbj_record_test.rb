require 'test_helper'

class DDBJRecordTest < ActiveSupport::TestCase
  def parse(fixture)
    file_fixture("ddbj_record/#{fixture}").open { DDBJRecord.parse(it) }
  end

  test 'round-trip: parse -> generate -> parse reproduces the same data' do
    record   = parse('example.json')
    file     = DDBJRecord.generate(record)
    reparsed = DDBJRecord.parse(file)

    assert_equal record, reparsed
  ensure
    file&.close!
  end

  test 'builds correct Data types' do
    record = parse('example.json')

    assert_kind_of DDBJRecord::Root,                      record
    assert_kind_of DDBJRecord::Provenance,                record.provenance
    assert_kind_of DDBJRecord::Submission,                record.submission
    assert_kind_of DDBJRecord::ApplicationIdentification, record.submission.application_identification
    assert_kind_of DDBJRecord::Sequences,                 record.sequences
    assert_kind_of DDBJRecord::Source,                    record.sequences.common_source

    entry = record.sequences.entries.first

    assert_kind_of DDBJRecord::Entry, entry

    source_feature = entry.source_features.first

    assert_kind_of DDBJRecord::SourceFeature, source_feature
    assert_kind_of DDBJRecord::Source,        source_feature.source

    assert_equal 'Homo sapiens', source_feature.source.organism
  end

  test 'parses features and qualifiers as Data objects from invalid.json' do
    record  = parse('invalid.json')
    feature = record.features.first

    assert_kind_of DDBJRecord::Feature, feature

    assert_equal 'bar', feature.type

    qualifier = feature.qualifiers['baz'].first

    assert_kind_of DDBJRecord::Qualifier, qualifier

    assert_equal '', qualifier.value
  end
end
