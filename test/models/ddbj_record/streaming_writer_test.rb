require 'test_helper'

class DDBJRecord::StreamingWriterTest < ActiveSupport::TestCase
  test 'produces identical output to Writer for the same data' do
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    expected_io = StringIO.new
    DDBJRecord::Writer.new(expected_io).write record
    expected = expected_io.string

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    actual_io = StringIO.new

    DDBJRecord::StreamingWriter.new(actual_io).write metadata, features: record.features do |w|
      record.sequences.entries.each do |entry|
        w << entry
      end
    end

    actual = actual_io.string

    assert_equal Oj.load(expected), Oj.load(actual)
  end

  test 'produces parseable JSON' do
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    io = StringIO.new

    DDBJRecord::StreamingWriter.new(io).write metadata, features: record.features do |w|
      record.sequences.entries.each do |entry|
        w << entry
      end
    end

    reparsed = DDBJRecord.parse(StringIO.new(io.string))

    assert_equal record, reparsed
  end

  test 'works with multi_entry fixture' do
    record = file_fixture('ddbj_record/multi_entry.json').open { DDBJRecord.parse(it) }

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    io = StringIO.new

    DDBJRecord::StreamingWriter.new(io).write metadata, features: record.features do |w|
      record.sequences.entries.each do |entry|
        w << entry
      end
    end

    reparsed = DDBJRecord.parse(StringIO.new(io.string))

    assert_equal record.sequences.entries.map(&:id), reparsed.sequences.entries.map(&:id)
    assert_equal record.features.map(&:id), reparsed.features.map(&:id)
  end
end
