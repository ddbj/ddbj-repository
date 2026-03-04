require 'rails_helper'

RSpec.describe DDBJRecord do
  def parse(fixture)
    file_fixture("ddbj_record/#{fixture}").open { DDBJRecord.parse(it) }
  end

  describe '.parse' do
    context 'example.json' do
      subject(:record) { parse('example.json') }

      example 'round-trip: parse → as_json matches original JSON' do
        original = JSON.parse(file_fixture('ddbj_record/example.json').read)

        expect(record.as_json).to eq(original)
      end

      example 'builds correct Data types' do
        expect(record).to be_a(DDBJRecord::Root)
        expect(record.submission).to be_a(DDBJRecord::Submission)
        expect(record.submission.application_identification).to be_a(DDBJRecord::ApplicationIdentification)
        expect(record.sequences).to be_a(DDBJRecord::Sequences)

        entry = record.sequences.entries.first
        expect(entry).to be_a(DDBJRecord::Entry)

        qualifier = entry.source_qualifiers['organism'].first
        expect(qualifier).to be_a(DDBJRecord::Qualifier)
      end
    end

    context 'invalid.json' do
      subject(:record) { parse('invalid.json') }

      example 'parses features and qualifiers as Data objects' do
        feature = record.features.first
        expect(feature).to be_a(DDBJRecord::Feature)
        expect(feature.type).to eq('bar')

        qualifier = feature.qualifiers['baz'].first
        expect(qualifier).to be_a(DDBJRecord::Qualifier)
        expect(qualifier.value).to eq('')
      end
    end
  end

  describe 'Data#with + as_json (apply job flow)' do
    subject(:record) { parse('example.json') }

    example 'updated entries are reflected in as_json' do
      entries = record.sequences.entries.map {|entry|
        entry.with(
          accession:    'AB000001',
          locus:        'AB000001',
          version:      1,
          last_updated: '2026-01-15T00:00:00+09:00'
        )
      }

      new_record = record.with(sequences: record.sequences.with(entries:))
      json       = new_record.as_json

      json['sequences']['entries'].each do |entry|
        expect(entry['accession']).to eq('AB000001')
        expect(entry['locus']).to eq('AB000001')
        expect(entry['version']).to eq(1)
        expect(entry['last_updated']).to eq('2026-01-15T00:00:00+09:00')
      end
    end
  end
end
