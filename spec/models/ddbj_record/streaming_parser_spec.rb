require 'rails_helper'

RSpec.describe DDBJRecord::StreamingParser do
  def parser_for(fixture)
    DDBJRecord::StreamingParser.new(file_fixture("ddbj_record/#{fixture}"))
  end

  describe 'with multi_entry.json' do
    subject(:parser) { parser_for('multi_entry.json') }

    describe '#metadata' do
      subject(:meta) { parser.metadata }

      it 'returns a DDBJRecord::Root' do
        expect(meta).to be_a(DDBJRecord::Root)
      end

      it 'parses submission' do
        expect(meta.submission).to be_a(DDBJRecord::Submission)
        expect(meta.submission.division).to eq('PLN')
        expect(meta.submission.trad_submission_category).to eq('GNM')
      end

      it 'parses experiments' do
        expect(meta.experiments.size).to eq(1)
        expect(meta.experiments.first).to be_a(DDBJRecord::Experiment)
        expect(meta.experiments.first.experiment_attributes['assembly_method']).to eq('SPAdes v 3.15')
      end

      it 'parses common_source' do
        cs = meta.sequences.common_source

        expect(cs).to be_a(DDBJRecord::Source)
        expect(cs.organism).to eq('Testus plantus')
        expect(cs.mol_type).to eq('genomic DNA')
      end

      it 'returns empty entries and features' do
        expect(meta.sequences.entries).to eq([])
        expect(meta.features).to eq([])
      end
    end

    describe '#features_by_sequence_id' do
      subject(:features) { parser.features_by_sequence_id }

      it 'groups features by sequence_id' do
        expect(features.keys).to contain_exactly('TST1ch01', 'TST1ch02')
      end

      it 'builds DDBJRecord::Feature objects' do
        feat = features['TST1ch01'].first

        expect(feat).to be_a(DDBJRecord::Feature)
        expect(feat.type).to eq('assembly_gap')
        expect(feat.location).to eq('20..30')
      end

      it 'builds nested Qualifier objects' do
        qual = features['TST1ch01'].first.qualifiers['estimated_length'].first

        expect(qual).to be_a(DDBJRecord::Qualifier)
        expect(qual.value).to eq('known')
      end
    end

    describe '#each_entry' do
      it 'yields DDBJRecord::Entry objects' do
        entries = parser.each_entry.to_a

        expect(entries).to all be_a(DDBJRecord::Entry)
      end

      it 'yields entries in order' do
        ids = parser.each_entry.map(&:id)

        expect(ids).to eq(%w[TST1ch01 TST1ch02 TST1u001])
      end

      it 'preserves entry fields' do
        entry = parser.each_entry.first

        expect(entry.name).to eq('TST1ch01')
        expect(entry.topology).to eq('linear')
        expect(entry.sequence).to eq('atgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgcatgc')
        expect(entry.tax_id).to eq(12345)
      end

      it 'builds nested source_features' do
        entry = parser.each_entry.first
        sf    = entry.source_features.first

        expect(sf).to be_a(DDBJRecord::SourceFeature)
        expect(sf.location).to eq('1..E')
        expect(sf.definition).to eq(['@@[organism]@@ @@[cultivar]@@ DNA, chromosome @@[chromosome]@@'])
      end

      it 'returns an enumerator without a block' do
        expect(parser.each_entry).to be_a(Enumerator)
        expect(parser.each_entry.count).to eq(3)
      end
    end
  end

  describe 'with example.json (ST.26 format)' do
    subject(:parser) { parser_for('example.json') }

    it 'parses metadata' do
      expect(parser.metadata.submission.division).to eq('PAT')
    end

    it 'streams entries with nested source objects' do
      entry = parser.each_entry.first
      sf    = entry.source_features.first

      expect(sf.source).to be_a(DDBJRecord::Source)
      expect(sf.source.organism).to eq('Homo sapiens')
      expect(sf.source.mol_type).to eq('genomic DNA')
    end

    it 'yields the same entries as DDBJRecord.parse' do
      full = File.open(file_fixture('ddbj_record/example.json')) { DDBJRecord.parse(it) }

      parser.each_entry.zip(full.sequences.entries).each do |streamed, expected|
        expect(streamed).to eq(expected)
      end
    end
  end

  describe 'with Writer-generated output' do
    it 'handles indent: 2 formatting' do
      original = File.open(file_fixture('ddbj_record/example.json')) { DDBJRecord.parse(it) }

      file = DDBJRecord.generate(original)

      begin
        parser  = DDBJRecord::StreamingParser.new(file.path)
        entries = parser.each_entry.to_a

        expect(entries.size).to eq(2)
        expect(entries.map(&:id)).to eq(original.sequences.entries.map(&:id))
        expect(entries.map(&:sequence)).to eq(original.sequences.entries.map(&:sequence))
      ensure
        file.close!
      end
    end
  end
end
