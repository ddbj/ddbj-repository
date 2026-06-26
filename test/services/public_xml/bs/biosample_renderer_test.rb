require 'test_helper'

class PublicXML::Bs::BioSampleRendererTest < ActiveSupport::TestCase
  test 'emits BioSample with description / organism / attributes; suppresses Owner Contacts' do
    sample = samples(:second).tap { it.update!(accession: 'SAMD00000777', release_date: Date.new(2026, 3, 1), dist_date: Date.new(2026, 6, 1)) }

    record = {
      'submission' => {
        'submitters' => [{
          'email'         => 'curator@example.com',
          'first_name'    => 'Ada',
          'organizations' => [{'name' => 'DDBJ'}]
        }]
      },
      'samples'    => [{
        'accession'   => 'SAMD00000777',
        'alias'       => 'fixture-sample-2',
        'title'       => 'A sample title',
        'description' => 'A sample description',
        'package'     => 'MIxS.air.5.0',
        'organism'    => {'taxonomy_id' => 9606, 'name' => 'Homo sapiens'},
        'attributes'  => [
          {'name' => 'collection_date', 'value' => '2026-03-01'},
          {'name' => 'geo_loc_name',    'value' => 'Japan'}
        ]
      }]
    }

    node = PublicXML::Bs::BioSampleRenderer.new(record:, row: sample).call

    assert_equal 'BioSample', node.name
    assert_equal 'SAMD00000777', node['accession']
    assert_equal '2026-03-01',   node['publication_date']
    assert_equal '2026-06-01',   node['last_update']

    primary_id = node.at_xpath('./Ids/Id[@is_primary="1"]')
    assert_equal 'SAMD00000777', primary_id.text
    assert_equal 'DDBJ',         primary_id['db']

    alias_id = node.at_xpath('./Ids/Id[@db_label="Sample name"]')
    assert_equal 'fixture-sample-2', alias_id.text

    desc = node.at_xpath('./Description')
    assert_equal 'A sample title',       desc.at_xpath('./Title').text
    assert_equal 'A sample description', desc.at_xpath('./Comment/Paragraph').text
    assert_equal '9606',                 desc.at_xpath('./Organism/@taxonomy_id').value
    assert_equal 'Homo sapiens',         desc.at_xpath('./Organism/OrganismName').text

    assert_equal 'DDBJ',         node.at_xpath('./Owner/Name').text
    assert_nil   node.at_xpath('./Owner/Contacts'), 'BS public XML must strip Contacts (bsbatch parity)'
    assert_nil   node.at_xpath('./Owner/Contact'),  'BS public XML must strip individual Contact too'

    assert_equal 'MIxS.air.5.0', node.at_xpath('./Package').text

    attrs = node.xpath('./Attributes/Attribute').map { [it['attribute_name'], it.text] }
    assert_equal [%w[collection_date 2026-03-01], %w[geo_loc_name Japan]], attrs
  end

  test 'falls back last_update to release_date when dist_date is nil' do
    sample = samples(:second).tap { it.update!(accession: 'SAMD00000778', release_date: Date.new(2026, 3, 1), dist_date: nil) }

    record = {'samples' => [{'alias' => sample.sample_name}]}
    node   = PublicXML::Bs::BioSampleRenderer.new(record:, row: sample).call

    assert_equal '2026-03-01', node['publication_date']
    assert_equal '2026-03-01', node['last_update']
  end

  test 'returns nil when the v3 record has no sample with a matching alias' do
    sample = samples(:second).tap { it.update!(accession: 'SAMD00000999') }

    record = {'samples' => [{'alias' => 'no-such-alias'}]}

    assert_nil PublicXML::Bs::BioSampleRenderer.new(record:, row: sample).call
  end
end
