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

  let(:validation) { create(:validation) }

  example 'ok' do
    seq = create_seq(validation)
    ann = create_ann(validation)

    Database::Trad::Validator.new.validate validation
    [seq, ann].each &:reload

    expect(seq).to have_attributes(
      validity:           'valid',
      validation_details: nil
    )

    expect(ann).to have_attributes(
      validity:           'valid',
      validation_details: nil
    )
  end

  describe 'ext' do
    example do
      seq = create_seq(validation, name: 'foo.bar')
      ann = create_ann(validation, name: 'foo.baz')

      Database::Trad::Validator.new.validate validation
      [seq, ann].each &:reload

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
          'message'  => 'The extension should be one of the following: .ann, .annt.tsv, .ann.txt'
        ]
      )
    end
  end

  describe 'pairwise' do
    example 'not paired' do
      seq = create_seq(validation, name: 'foo.fasta')
      ann = create_ann(validation, name: 'bar.ann')

      Database::Trad::Validator.new.validate validation
      [seq, ann].each &:reload

      expect(seq).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'There is no corresponding annotation file.'
        ]
      )

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'There is no corresponding sequence file.'
        ]
      )
    end

    example 'duplicate seq' do
      seq1 = create_seq(validation, name: 'foo.fasta')
      seq2 = create_seq(validation, name: 'foo.seq')
      ann  = create_ann(validation, name: 'foo.ann')

      Database::Trad::Validator.new.validate validation
      [seq1, seq2, ann].each &:reload

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
    end

    example 'combined' do
      seq1 = create_seq(validation, name: 'foo.fasta')
      seq2 = create_seq(validation, name: 'foo.seq')

      Database::Trad::Validator.new.validate validation
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
          }
        )
      )
    end
  end

  describe 'seq' do
    example 'no entries' do
      seq = create_seq(validation, content: '')
      ann = create_ann(validation)

      Database::Trad::Validator.new.validate validation
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
    example 'missing contact person' do
      seq = create_seq(validation)
      ann = create_ann(validation, content: '')

      Database::Trad::Validator.new.validate validation
      ann.reload

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'Contact person information (contact, email, institute) is missing.'
        ]
      )
    end

    example 'missing contact person (partial)' do
      seq = create_seq(validation)

      ann = create_ann(validation, content: <<~ANN)
        COMMON	SUBMITTER		contact	Alice Liddell
        			email	alice@example.com
      ANN

      Database::Trad::Validator.new.validate validation
      ann.reload

      expect(ann).to have_attributes(
        validity: 'invalid',

        validation_details: [
          'severity' => 'error',
          'message'  => 'Contact person information (contact, email, institute) is missing.'
        ]
      )
    end
  end
end
