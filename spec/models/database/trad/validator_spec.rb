require 'rails_helper'

RSpec.describe Database::Trad::Validator, type: :model do
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

  def create_ann(validation, name: 'foo.ann', content: <<~ANN)
    COMMON	SUBMITTER		contact	Alice Liddell
    			email	alice@example.com
    			institute	Wonderland Inc.
  ANN

    create(:obj, validation:, _id: 'Annotation', file: uploaded_file(name:, content:))
  end

  let(:validation) { create(:validation, id: 42) }

  example 'ok' do
    create_seq validation, name: 'foo.fasta'
    create_ann validation, name: 'foo.ann'

    Database::Trad::Validator.new.validate validation
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
          path: 'foo.ann',
          url:  'http://www.example.com/api/validations/42/files/foo.ann'
        }
      }
    )
  end

  describe 'ext' do
    example do
      create_seq validation, name: 'foo.bar'
      create_ann validation, name: 'foo.baz'

      Database::Trad::Validator.new.validate validation
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
            message:  'The extension should be one of the following: .ann, .annt.tsv, .ann.txt'
          ]
        )
      )
    end
  end

  describe 'pairwise' do
    example 'not paired' do
      create_seq validation, name: 'foo.fasta'
      create_ann validation, name: 'bar.ann'

      Database::Trad::Validator.new.validate validation
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
            message:  'There is no corresponding annotation file.'
          ]
        ),
        include(
          object_id: 'Annotation',
          validity:  'invalid',

          details: [
            code:     nil,
            severity: 'error',
            message:  'There is no corresponding sequence file.'
          ]
        )
      )
    end

    example 'duplicate seq' do
      create_seq validation, name: 'foo.fasta'
      create_seq validation, name: 'foo.seq'
      create_ann validation, name: 'foo.ann'

      Database::Trad::Validator.new.validate validation
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
        )
      )
    end

    example 'combined' do
      create_seq validation, name: 'foo.fasta'
      create_seq validation, name: 'foo.seq'

      Database::Trad::Validator.new.validate validation
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
            }
          ]
        )
      )
    end
  end

  describe 'seq' do
    example 'no entries' do
      create_seq validation, content: ''
      create_ann validation

      Database::Trad::Validator.new.validate validation
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
        )
      )
    end
  end

  describe 'ann' do
    example 'missing contact person' do
      create_seq validation
      create_ann validation, content: ''

      Database::Trad::Validator.new.validate validation
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
            message:  'Contact person information (contact, email, institute) is missing.'
          ]
        )
      )
    end

    example 'missing contact person (partial)' do
      create_seq validation

      create_ann validation, content: <<~ANN
        COMMON	SUBMITTER		contact	Alice Liddell
        			email	alice@example.com
      ANN

      Database::Trad::Validator.new.validate validation
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
            message:  'Contact person information (contact, email, institute) is missing.'
          ]
        )
      )
    end

    example 'duplicate contact' do
      create_seq validation

      create_ann validation, content: <<~ANN
        COMMON	SUBMITTER		contact	Alice Liddell
        			contact	ALice Liddell
      ANN

      Database::Trad::Validator.new.validate validation
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
            message:  'Contact person information (contact, email, institute) is duplicated.'
          ]
        )
      )
    end

    example 'duplicate email' do
      create_seq validation

      create_ann validation, content: <<~ANN
        COMMON	SUBMITTER		contact	Alice Liddell
        			email	alice@example.com
        			email	alice@example.com
      ANN

      Database::Trad::Validator.new.validate validation
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
            message:  'Contact person information (contact, email, institute) is duplicated.'
          ]
        )
      )
    end

    example 'duplicate institute' do
      create_seq validation

      create_ann validation, content: <<~ANN
        COMMON	SUBMITTER		contact	Alice Liddell
        			institute	Wonderland Inc.
        			institute	Wonderland Inc.
      ANN

      Database::Trad::Validator.new.validate validation
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
            message:  'Contact person information (contact, email, institute) is duplicated.'
          ]
        )
      )
    end
  end
end
