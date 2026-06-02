require 'test_helper'

class BioProject::ConverterTest < ActiveSupport::TestCase
  test 'PSUB000604 (PRJDB502, primary) — minimum field mapping' do
    xml         = file_fixture('data_migration/bio_project/PSUB000604.xml').read
    project_row = {project_type: 'primary'}

    record = BioProject::Converter.new(xml:, project_row:).call

    assert_equal 'v3',                                     record['schema_version']
    assert_equal({'source_format' => 'dway_bp_xml'},       record['provenance'])

    project = record.fetch('project')
    assert_equal 'PRJDB502',                               project['accession']
    assert_equal 'primary',                                project['project_type']
    assert_equal 'Chromosome Mycobacterium avium sequencing', project['title']
    assert_match(/Mycobacterium avium complex/,            project['description'])
    assert_equal ['MAH'],                                  project['locus_tag_prefix']
    assert_equal({'taxonomy_id' => 1229671, 'name' => 'Mycobacterium avium subsp. hominissuis TH135'},
                 project['organism'])

    submitters = record.dig('submission', 'submitters')
    assert_equal 2, submitters.size
    assert_equal({'email' => 'sample-1@example.test', 'first' => 'Sample-First-1', 'last' => 'Sample-Last-1'},
                 submitters[0])
    assert_equal({'email' => 'sample-2@example.test', 'first' => 'Sample-First-2', 'last' => 'Sample-Last-2'},
                 submitters[1])
  end

  test 'canonicalises cleanly via the production pipeline' do
    xml    = file_fixture('data_migration/bio_project/PSUB000604.xml').read
    record = BioProject::Converter.new(xml:, project_row: {project_type: 'primary'}).call

    # If any string in the converter output trips §2 normalisation (control
    # chars, alphabet-restricted sequence path, etc.) this raises. Acts as a
    # smoke test that converter output is canon-compatible.
    bytes = DDBJRecord::Canonicalizer.canonicalize(record)

    assert_kind_of String, bytes
    assert_includes bytes, '"accession":"PRJDB502"'
  end
end
