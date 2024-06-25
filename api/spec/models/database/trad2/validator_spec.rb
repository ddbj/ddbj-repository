require 'rails_helper'

RSpec.describe Database::Trad2::Validator, type: :model do
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

  let(:validation) { create(:validation, id: 42) }

  example 'ok' do
    create_seq  validation, name: 'foo.fasta'
    create_ann  validation, name: 'foo.gff'
    create_meta validation, name: 'foo.tsv'

    Database::Trad2::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      {
        object_id: '_base',
        validity:  nil,
        details:   [],
        file:      nil
      },
      {
        object_id: 'Sequence',
        validity:  'valid',
        details:   [],

        file: {
          path: 'foo.fasta',
          url:  'http://www.example.com/api/validations/42/files/foo.fasta'
        }
      },
      {
        object_id: 'Annotation',
        validity:  'valid',
        details:   [],

        file: {
          path: 'foo.gff',
          url:  'http://www.example.com/api/validations/42/files/foo.gff'
        }
      },
      {
        object_id: 'Metadata',
        validity:  'valid',
        details:   [],

        file: {
          path: 'foo.tsv',
          url:  'http://www.example.com/api/validations/42/files/foo.tsv'
        }
      }
    )
  end

  describe 'ext' do
    example do
      create_seq  validation, name: 'foo.bar'
      create_ann  validation, name: 'foo.baz'
      create_meta validation, name: 'foo.qux'

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'The extension should be one of the following: .fasta, .seq.fa, .fa, .fna, .seq'
          ]
        ),
        include(
          object_id: 'Annotation',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'The extension should be one of the following: .gff'
          ]
        ),
        include(
          object_id: 'Metadata',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'The extension should be one of the following: .tsv'
          ]
        )
      )
    end
  end

  describe 'n-wise' do
    example 'not paired' do
      create_seq  validation, name: 'foo.fasta'
      create_ann  validation, name: 'bar.gff'
      create_meta validation, name: 'baz.tsv'

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding annotation file.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding metadata file.'
            }
          ]
        ),
        include(
          object_id: 'Annotation',
          validity:  'invalid',

          details: [
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding sequence file.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding metadata file.'
            }
          ]
        ),
        include(
          object_id: 'Metadata',
          validity:  'invalid',

          details: [
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding sequence file.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding annotation file.'
            }
          ]
        )
      )
    end

    example 'duplicate seq' do
      create_seq  validation, name: 'foo.fasta'
      create_seq  validation, name: 'foo.seq'
      create_ann  validation, name: 'foo.gff'
      create_meta validation, name: 'foo.tsv'

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'Duplicate sequence files with the same name exist.'
          ]
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'Duplicate sequence files with the same name exist.'
          ]
        ),
        include(
          object_id: 'Annotation',
          validity:  'valid'
        ),
        include(
          object_id: 'Metadata',
          validity:  'valid'
        )
      )
    end

    example 'combined' do
      create_seq validation, name: 'foo.fasta'
      create_seq validation, name: 'foo.seq'

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            {
              code:     nil,
              severity: 'error',
              message:  'Duplicate sequence files with the same name exist.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding annotation file.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding metadata file.'
            }
          ]
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            {
              code:     nil,
              severity: 'error',
              message:  'Duplicate sequence files with the same name exist.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding annotation file.'
            },
            {
              code:     nil,
              severity: 'error',
              message:  'There is no corresponding metadata file.'
            }
          ]
        )
      )
    end
  end

  describe 'seq' do
    example 'no entries' do
      create_seq  validation, content: ''
      create_ann  validation
      create_meta validation

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'No entries found.'
          ]
        ),
        include(
          object_id: 'Annotation',
          validity:  'valid'
        ),
        include(
          object_id: 'Metadata',
          validity:  'valid'
        )
      )
    end
  end

  describe 'ann' do
    example 'invalid' do
      create_seq  validation
      create_ann  validation, content: 'foo'
      create_meta validation

      Database::Trad2::Validator.new.validate validation
      validation.reload

      expect(validation.results).to contain_exactly(
        include(
          object_id: '_base',
          validity:  nil
        ),
        include(
          object_id: 'Sequence',
          validity:  'valid'
        ),
        include(
          object_id: 'Annotation',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'Line 1: Custom { kind: InvalidData, error: InvalidRecord(MissingField(Source)) }'
          ]
        ),
        include(
          object_id: 'Metadata',
          validity:  'valid'
        )
      )
    end
  end
end
