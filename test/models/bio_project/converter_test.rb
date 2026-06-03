require 'test_helper'

class BioProject::ConverterTest < ActiveSupport::TestCase
  PSUB604_XML = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB000604.xml').freeze
  PSUB671_XML = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB002671.xml').freeze

  def convert(path = PSUB604_XML, project_type: 'primary')
    BioProject::Converter.new(xml: File.read(path), project_row: {project_type:}).call
  end

  test 'PSUB000604 (PRJDB502, primary) — top-level field mapping' do
    record = convert

    assert_equal 'v3',                                        record['schema_version']
    assert_equal({'source_format' => 'dway_bp_xml'},          record['provenance'])

    project = record.fetch('project')
    assert_equal 'PRJDB502',                                  project['accession']
    assert_equal 'primary',                                   project['project_type']
    assert_equal 'Chromosome Mycobacterium avium sequencing', project['title']
    assert_match(/Mycobacterium avium complex/,               project['description'])
    assert_equal ['MAH'],                                     project['locus_tag_prefix']
    assert_equal({'taxonomy_id' => 1229671, 'name' => 'Mycobacterium avium subsp. hominissuis TH135'},
                 project['organism'])
  end

  test 'PSUB000604 — Grant lifts id / title / agency' do
    grants = convert.dig('project', 'grants')

    assert_equal 1,                                            grants.size
    assert_equal '24590164',                                   grants[0]['id']
    assert_equal 'Comparative genome analysis of nontuberculous mycobacteria and clinical application',
                 grants[0]['title']
    assert_equal 'Japan Society for the Promotion of Science', grants[0]['agency']
  end

  test 'PSUB000604 — Relevance flattens tag names to lowercase array' do
    assert_equal ['medical'], convert.dig('project', 'relevance')
  end

  test 'PSUB000604 — Target attrs + Method + ProjectDataTypeSet' do
    target = convert.dig('project', 'target')

    assert_equal 'eMonoisolate',        target['sample_scope']
    assert_equal 'eGenome',             target['material']
    assert_equal 'eWhole',              target['capture']
    assert_equal 'eSequencing',         target['method']
    assert_equal ['Genome Sequencing'], target['data_types']
  end

  test 'PSUB000604 — Submitters carry shared Organization' do
    submitters = convert.dig('submission', 'submitters')

    assert_equal 2, submitters.size
    assert_equal({'email' => 'sample-1@example.test', 'first' => 'Sample-First-1', 'last' => 'Sample-Last-1',
                  'organization' => {'name' => 'Meijo University faculty of pharmacy'}},
                 submitters[0])
    assert_equal 'Meijo University faculty of pharmacy', submitters[1]['organization']['name']
  end

  test 'PSUB002671 — Publication lifts pubmed_id + status (Reference body absent)' do
    pubs = convert(PSUB671_XML).dig('project', 'publications')

    assert_equal 1,             pubs.size
    assert_equal '23936076',    pubs[0]['pubmed_id']
    assert_equal 'ePublished',  pubs[0]['status']
    refute_includes pubs[0].keys, 'doi'
  end

  test 'PSUB002671 — Relevance Other carries through' do
    assert_equal ['other'], convert(PSUB671_XML).dig('project', 'relevance')
  end

  test 'canonicalises cleanly via the production pipeline' do
    bytes = DDBJRecord::Canonicalizer.canonicalize(convert)

    assert_kind_of String, bytes
    assert_includes bytes, '"accession":"PRJDB502"'
    assert_includes bytes, '"agency":"Japan Society for the Promotion of Science"'
  end
end
