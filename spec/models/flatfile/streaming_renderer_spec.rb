require 'rails_helper'

RSpec.describe Flatfile::StreamingRenderer do
  def build_record
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    submission = record.submission.with(
      publication_date: '2026-06-01',
      applicant_name:   'Test Applicant',
      invention_title:  'Test Invention',
      inventor_name:    'Test Inventor'
    )

    entries = record.sequences.entries.map.with_index(1) {|entry, i|
      entry.with(
        accession:    "AB00000#{i}",
        locus:        "AB00000#{i}",
        version:      1,
        last_updated: '2026-06-01'
      )
    }

    record.with(
      submission: submission,
      sequences:  record.sequences.with(entries:)
    )
  end

  it 'produces identical output to Root#render' do
    record  = build_record
    entries = record.sequences.entries

    expected = Flatfile.render(record, entries).read

    features_by_sequence_id = record.features.group_by(&:sequence_id)

    io = StringIO.new
    renderer = described_class.new(record, features_by_sequence_id, io)

    entries.each { renderer.render_entry(it) }

    expect(io.string).to eq(expected)
  end
end
