require 'rails_helper'

RSpec.describe DDBJRecord::StreamingWriter do
  it 'produces identical output to Writer for the same data' do
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    expected_io = StringIO.new
    DDBJRecord::Writer.new(expected_io).write(record)
    expected = expected_io.string

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    actual_io = StringIO.new

    DDBJRecord::StreamingWriter.new(actual_io).write(metadata, features: record.features) do |w|
      record.sequences.entries.each { w << it }
    end

    actual = actual_io.string

    expect(Oj.load(actual)).to eq(Oj.load(expected))
  end

  it 'produces parseable JSON' do
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    io = StringIO.new

    DDBJRecord::StreamingWriter.new(io).write(metadata, features: record.features) do |w|
      record.sequences.entries.each { w << it }
    end

    reparsed = DDBJRecord.parse(StringIO.new(io.string))

    expect(reparsed).to eq(record)
  end

  it 'works with multi_entry fixture' do
    record = file_fixture('ddbj_record/multi_entry.json').open { DDBJRecord.parse(it) }

    metadata = record.with(
      sequences: record.sequences.with(entries: []),
      features:  []
    )

    io = StringIO.new

    DDBJRecord::StreamingWriter.new(io).write(metadata, features: record.features) do |w|
      record.sequences.entries.each { w << it }
    end

    reparsed = DDBJRecord.parse(StringIO.new(io.string))

    expect(reparsed.sequences.entries.map(&:id)).to eq(record.sequences.entries.map(&:id))
    expect(reparsed.features.map(&:id)).to eq(record.features.map(&:id))
  end
end
