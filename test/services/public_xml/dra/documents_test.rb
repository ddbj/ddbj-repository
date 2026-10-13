require 'test_helper'

class PublicXML::DRA::DocumentsTest < ActiveSupport::TestCase
  def record = JSON.parse(file_fixture('dra/record/DRA000001.json').read)

  def documents(record = self.record) = PublicXML::DRA::Documents.call(record).transform_values { Nokogiri::XML(it) }

  def named(element, *attributes) = attributes.map { element[it] }

  # As D-way's release left them out of the public copy.
  test 'leaves out who to write to, what was asked for, and the names of the files sent' do
    documents = documents()

    assert_equal 'RNA-seq of liver tissue', documents['submission'].at_xpath('/SUBMISSION/TITLE').content
    assert_nil documents['submission'].at_xpath('//CONTACTS | //ACTIONS')
    assert_nil documents['run'].at_xpath('//DATA_BLOCK')
  end

  # The alias is the submitter's own name for an object; the public copy
  # names everything by its accession, a reference included.
  test 'names every object by its accession, where it is and where it is referred to' do
    documents = documents()

    assert_equal %w[DRA000001 DRA000001], named(documents['submission'].root, 'alias', 'accession')
    assert_equal %w[DRX000001 DRX000001], named(documents['experiment'].at_xpath('//EXPERIMENT'), 'alias', 'accession')
    assert_equal %w[DRX000001 DRX000001], named(documents['run'].at_xpath('//EXPERIMENT_REF'), 'refname', 'accession')
    assert_equal %w[PRJDB000001 PRJDB000001], named(documents['experiment'].at_xpath('//STUDY_REF'), 'refname', 'accession')
  end

  # D-way set the refname to the accession whatever it had been.
  test 'a reference naming nothing that has an accession keeps no alias of the submitter\'s' do
    unnamed = record.tap { it['relations'][0]['target'] = {'db' => 'project', 'id' => 'my-project'} }

    study_ref = documents(unnamed)['experiment'].at_xpath('//STUDY_REF')

    assert_nil study_ref['refname']
    assert_nil study_ref['accession']
  end

  test 'a pool member and an analysis target named by alias are named by accession, a target naming nothing dropped' do
    named = record.tap {
      it['samples']     = [{'alias' => 'liver', 'accession' => 'SAMD00000009'}]
      it['experiments'][0]['pool'] = {'members' => [{'member_name' => 'a', 'sample' => {'id' => 'liver'}}]}
      it['relations'][1] = {'type' => 'part_of', 'source' => {'type' => 'experiment', 'alias' => 'tumor-exp'}, 'target' => {'db' => 'sample', 'id' => 'liver'}}
      it['analyses']    = [{'alias' => 'calls', 'accession' => 'DRZ000001', 'title' => 'Calls', 'description' => 'Variant calls', 'analysis_type' => 'reference_alignment'}]
      it['relations'] << {'type' => 'part_of', 'source' => {'type' => 'analysis', 'alias' => 'calls'}, 'target' => {'db' => 'project', 'accession' => 'PRJDB000001'}}
      it['relations'] << {'type' => 'derived_from', 'source' => {'type' => 'analysis', 'alias' => 'calls'}, 'target' => {'db' => 'run', 'id' => 'tumor-run'}}
      it['relations'] << {'type' => 'derived_from', 'source' => {'type' => 'analysis', 'alias' => 'calls'}, 'target' => {'db' => 'run', 'id' => 'no-such-run'}}
    }

    documents = PublicXML::DRA::Documents.send(:documents, named)

    assert_equal %w[SAMD00000009 SAMD00000009], named(documents['experiment'].at_xpath('//SAMPLE_DESCRIPTOR'), 'refname', 'accession')
    assert_equal [%w[DRR000001 DRR000001]], documents['analysis'].xpath('//TARGETS/TARGET').map { named(it, 'refname', 'accession') }, 'what names nothing dropped'
  end

  test 'is written in UTF-8' do
    xml = PublicXML::DRA::Documents.call(record.deep_merge('submission' => {'title' => '肝臓の RNA-seq'}))['submission']

    assert xml.start_with?('<?xml version="1.0" encoding="UTF-8"?>')
    assert_includes xml, '肝臓の RNA-seq'
  end

  test 'a document the version does not take is refused' do
    unknown = record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }

    error = assert_raises(PublicXML::DRA::Documents::Invalid) { documents(unknown) }

    assert_match(/\Aexperiment: .*LIBRARY_STRATEGY/, error.message)
  end
end
