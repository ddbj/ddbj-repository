require 'rails_helper'

RSpec.describe Trad2Validator, type: :model do
  def create_seq(validation, name: 'foo.fasta', content: <<~SEQ)
    >CLN01
    ggacaggctgccgcaggagccaggccgggagcaggaagaggcttcgggggagccggagaa
    ctgggccagatgcgcttcgtgggcgaagcctgaggaaaaagagagtgaggcaggagaatc
    gcttgaaccccggaggcggaaccgcactccagcctgggcgacagagtgagactta
    //
    >CLN02
    ctcacacagatgcgcgcacaccagtggttgtaacagaagcctgaggtgcgctcgtggtca
    gaagagggcatgcgcttcagtcgtgggcgaagcctgaggaaaaaatagtcattcatataa
    atttgaacacacctgctgtggctgtaactctgagatgtgctaaataaaccctctt
    //
  SEQ

    create(:obj, validation:, _id: 'Sequence', file: uploaded_file(name:, content:))
  end

  def create_ann(validation, name: 'foo.gff', content: <<~GFF)
    ##gff-version 3
    ##sequence-region chr1 1 30584173
    chr1	feature	gene	1	1967	.	-	.	ID=Mp1g00005a;Name=Mp1g00005a;locus_type=rRNA;note=partial
    chr1	feature	rRNA	1	1967	.	-	.	ID=Mp1g00005a.1;Name=Mp1g00005a.1;Parent=Mp1g00005a;note=partial;product=26S ribosomal RNA
    chr1	feature	exon	1	1967	.	-	.	ID=Mp1g00005a.1.exon1;Name=Mp1g00005a.1.exon1;Parent=Mp1g00005a.1;note=partial
  GFF

    create(:obj, validation:, _id: 'Annotation', file: uploaded_file(name:, content:))
  end

  def create_meta(validation, name: 'foo.tsv', content: '')
    create(:obj, validation:, _id: 'Metadata', file: uploaded_file(name:, content:))
  end

  let(:validation) { create(:validation) }

  example 'ok' do
    seq  = create_seq(validation)
    ann  = create_ann(validation)
    meta = create_meta(validation)

    Trad2Validator.new.validate validation
    [seq, ann, meta].each &:reload

    expect(seq).to have_attributes(
      validity:           'valid',
      validation_details: nil
    )

    expect(ann).to have_attributes(
      validity:           'valid',
      validation_details: nil
    )

    expect(meta).to have_attributes(
      validity:           'valid',
      validation_details: nil
    )
  end

  describe 'ext' do
    example do
      seq  = create_seq(validation,  name: 'foo.bar')
      ann  = create_ann(validation,  name: 'foo.baz')
      meta = create_meta(validation, name: 'foo.qux')

      Trad2Validator.new.validate validation
      [seq, ann, meta].each &:reload

      expect(seq).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'The extension should be one of the following: .fasta, .seq.fa, .fa, .fna, .seq'
        ]
      )

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'The extension should be one of the following: .gff'
        ]
      )

      expect(meta).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'The extension should be one of the following: .tsv'
        ]
      )
    end
  end

  describe 'n-wise' do
    example 'not paired' do
      seq  = create_seq(validation,  name: 'foo.fasta')
      ann  = create_ann(validation,  name: 'bar.gff')
      meta = create_meta(validation, name: 'baz.tsv')

      Trad2Validator.new.validate validation
      [seq, ann, meta].each &:reload

      expect(seq).to have_attributes(
        validity: 'invalid',

        validation_details: [
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding annotation file.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding metadata file.'
          }
        ]
      )

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding sequence file.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding metadata file.'
          }
        ]
      )

      expect(meta).to have_attributes(
        validity: 'invalid',

        validation_details: [
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding sequence file.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding annotation file.'
          }
        ]
      )
    end

    example 'duplicate seq' do
      seq1 = create_seq(validation,  name: 'foo.fasta')
      seq2 = create_seq(validation,  name: 'foo.seq')
      ann  = create_ann(validation,  name: 'foo.gff')
      meta = create_meta(validation, name: 'foo.tsv')

      Trad2Validator.new.validate validation
      [seq1, seq2, ann, meta].each &:reload

      expect(seq1).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'Duplicate sequence files with the same name exist.'
        ]
      )

      expect(seq2).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'Duplicate sequence files with the same name exist.'
        ]
      )

      expect(ann).to have_attributes(
        validity:           'valid',
        validation_details: nil
      )

      expect(meta).to have_attributes(
        validity:           'valid',
        validation_details: nil
      )
    end

    example 'combined' do
      seq1 = create_seq(validation, name: 'foo.fasta')
      seq2 = create_seq(validation, name: 'foo.seq')

      Trad2Validator.new.validate validation
      [seq1, seq2].each &:reload

      expect(seq1).to have_attributes(
        validity: 'invalid',

        validation_details: contain_exactly(
          {
            'severity' => 'error',
            'message'  => 'Duplicate sequence files with the same name exist.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding annotation file.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding metadata file.'
          }
        )
      )

      expect(seq2).to have_attributes(
        validity: 'invalid',

        validation_details: contain_exactly(
          {
            'severity' => 'error',
            'message'  => 'Duplicate sequence files with the same name exist.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding annotation file.'
          },
          {
            'severity' => 'error',
            'message'  => 'There is no corresponding metadata file.'
          }
        )
      )
    end
  end

  describe 'seq' do
    example 'no entries' do
      seq = create_seq(validation, content: '')

      create_ann validation
      create_meta validation

      Trad2Validator.new.validate validation
      seq.reload

      expect(seq).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'No entries found.'
        ]
      )
    end
  end

  describe 'ann' do
    example 'invalid' do
      ann = create_ann(validation, content: 'foo')

      create_seq validation
      create_meta validation

      Trad2Validator.new.validate validation
      ann.reload

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'Line 1: Custom { kind: InvalidData, error: InvalidRecord(MissingField(Source)) }'
        ]
      )
    end
  end
end
