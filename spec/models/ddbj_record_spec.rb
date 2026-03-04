require 'rails_helper'

RSpec.describe DDBJRecord do
  def parse(fixture)
    file_fixture("ddbj_record/#{fixture}").open { DDBJRecord.parse(it) }
  end

  describe '.parse' do
    context 'example.json' do
      subject(:record) { parse('example.json') }

      example 'round-trip: parse → generate → parse reproduces the same data' do
        file       = DDBJRecord.generate(record)
        reparsed   = DDBJRecord.parse(file)

        expect(reparsed).to eq(record)
      ensure
        file&.close!
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

end
