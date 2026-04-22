require 'test_helper'

class FlatfileTest < ActiveSupport::TestCase
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

  test 'renders fallback applicant in JOURNAL and omits PA/PT/PI when nil' do
    record = file_fixture('ddbj_record/example.json').open { DDBJRecord.parse(it) }

    submission = record.submission.with(
      publication_date: '2026-06-01',
      applicant_name:   nil,
      invention_title:  nil,
      inventor_name:    nil
    )

    entries = record.sequences.entries.map.with_index(1) {|entry, i|
      entry.with(
        accession:    "AB00000#{i}",
        locus:        "AB00000#{i}",
        version:      1,
        last_updated: '2026-06-01'
      )
    }

    record = record.with(
      submission: submission,
      sequences:  record.sequences.with(entries:)
    )

    output = Flatfile.render(record, record.sequences.entries).read

    assert_includes output, "  JOURNAL   Patent: JP 2026123456-A 1 01-JUN-2026;\n            Applicants [Refer to the patent publication]\n"
    refute_match(/^ {12}PA /, output)
    refute_match(/^ {12}PT /, output)
    refute_match(/^ {12}PI /, output)
  end

  test 'renders flatfile from Data objects' do
    record = build_record
    output = Flatfile.render(record, record.sequences.entries).read

    assert_equal <<~FLAT, output
      LOCUS       AB000001                  21 bp    DNA     linear   PAT 01-JUN-2026
      DEFINITION  test sequence 1
      ACCESSION   AB000001
      VERSION     AB000001.1
      KEYWORDS    JP 2026123456-A/1.
      SOURCE      Homo sapiens (human)
        ORGANISM  Homo sapiens
                  Homo.
      REFERENCE   1  (bases 1 to 21)
        AUTHORS
        TITLE     Test Invention
        JOURNAL   Patent: JP 2026123456-A 1 01-JUN-2026;
                  Test Applicant
      COMMENT     OS   Homo sapiens
                  PN   JP 2026123456-A/1
                  PD   01-JUN-2026
                  PF   15-JAN-2026 JP 2026-123456
                  PA   Test Applicant
                  PT   Test Invention
                  PI   Test Inventor
                  PS   1
                  FH   Key             Location/Qualifiers
                  FT   source          1..21
                  FT                   /note="Forward Primer(test)"
      FEATURES             Location/Qualifiers
           source          1..21
                           /organism="Homo sapiens"
                           /mol_type="genomic DNA"
                           /db_xref="taxon:9606"
      BASE COUNT            5 a            5 c            6 g            5 t
      ORIGIN
              1 atgcgtagct agctagctag c
      //
      LOCUS       AB000002                  21 bp    DNA     linear   PAT 01-JUN-2026
      DEFINITION  test sequence 2
      ACCESSION   AB000002
      VERSION     AB000002.1
      KEYWORDS    JP 2026123456-A/2.
      SOURCE      Homo sapiens (human)
        ORGANISM  Homo sapiens
                  Homo.
      REFERENCE   1  (bases 1 to 21)
        AUTHORS
        TITLE     Test Invention
        JOURNAL   Patent: JP 2026123456-A 2 01-JUN-2026;
                  Test Applicant
      COMMENT     OS   Homo sapiens
                  PN   JP 2026123456-A/2
                  PD   01-JUN-2026
                  PF   15-JAN-2026 JP 2026-123456
                  PA   Test Applicant
                  PT   Test Invention
                  PI   Test Inventor
                  PS   2
                  FH   Key             Location/Qualifiers
      FEATURES             Location/Qualifiers
           source          1..21
                           /organism="Homo sapiens"
                           /mol_type="genomic DNA"
                           /db_xref="taxon:9606"
      BASE COUNT            6 a            4 c            5 g            6 t
      ORIGIN
              1 ttagcgtagc tagctagcta a
      //
    FLAT
  end
end
