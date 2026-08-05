require 'test_helper'

class PublicXML::Bp::PackageRendererTest < ActiveSupport::TestCase
  test 'emits PackageSet-shaped Package node with project + submission core' do
    record = {
      'submission' => {
        'submitters' => [{
          'email'         => 'curator@example.com',
          'first_name'    => 'Ada',
          'last_name'     => 'Lovelace',
          'organizations' => [{'name' => 'DDBJ', 'role' => 'owner', 'type' => 'center', 'url' => 'https://ddbj.nig.ac.jp'}]
        }],
        'hold_date'  => '2030-01-01'
      },
      'project'    => {
        'accession'        => 'PRJDB000123',
        'title'            => 'Walking skeleton',
        'description'      => 'BP public XML port from D-way',
        'locus_tag_prefix' => %w[ABCDE FGHIJ],
        'organism'         => {'taxonomy_id' => 9606, 'name' => 'Homo sapiens'},
        'grants'           => [{'id' => 'JP-001', 'title' => 'Grant title', 'agency' => 'JSPS'}],
        'publications'     => [{'pubmed_id' => '12345', 'status' => 'ePublished'}],
        'relevance'        => {'medical' => 'cancer research'},
        'target'           => {'sample_scope' => 'eMonoisolate', 'material' => 'eGenome', 'capture' => 'eWholeGenome', 'method' => 'eSequencing', 'data_types' => ['Genome Sequencing']}
      }
    }

    node = PublicXML::Bp::PackageRenderer.new(record:).call

    assert_equal 'Package', node.name

    # Project shell
    assert_equal 'PRJDB000123', node.at_xpath('./Project/Project/ProjectID/ArchiveID/@accession').value
    assert_equal 'DDBJ',        node.at_xpath('./Project/Project/ProjectID/ArchiveID/@archive').value

    # ProjectDescr
    descr = node.at_xpath('./Project/Project/ProjectDescr')
    assert_equal 'Walking skeleton',                descr.at_xpath('./Title').text
    assert_equal 'BP public XML port from D-way',   descr.at_xpath('./Description').text
    assert_equal %w[ABCDE FGHIJ],                   descr.xpath('./LocusTagPrefix').map(&:text)
    assert_equal '2030-01-01',                      descr.at_xpath('./ProjectReleaseDate').text

    grant = descr.at_xpath('./Grant')
    assert_equal 'JP-001',      grant['GrantId']
    assert_equal 'Grant title', grant.at_xpath('./Title').text
    assert_equal 'JSPS',        grant.at_xpath('./Agency').text

    pub = descr.at_xpath('./Publication')
    assert_equal '12345',     pub['id']
    assert_equal 'ePublished', pub['status']
    assert_equal 'ePubmed',   pub.at_xpath('./Reference/DbType').text

    # `medical` should be re-titleized to `Medical` for consumer compatibility
    assert_equal 'cancer research', descr.at_xpath('./Relevance/Medical').text

    # Target
    target = node.at_xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Target')
    assert_equal 'eMonoisolate', target['sample_scope']
    assert_equal 'eGenome',      target['material']
    assert_equal 'eWholeGenome', target['capture']
    assert_equal '9606',         target.at_xpath('./Organism/@taxID').value
    assert_equal 'Homo sapiens', target.at_xpath('./Organism/OrganismName').text

    assert_equal 'eSequencing', node.at_xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Method/@method_type').value

    data_types = node.xpath('./Project/Project/ProjectType/ProjectTypeSubmission/ProjectDataTypeSet/DataType').map(&:text)
    assert_equal ['Genome Sequencing'], data_types

    # Submitters
    contact = node.at_xpath('./Submission/Submission/Description/Organization/Contact')
    assert_equal 'curator@example.com', contact['email']
    assert_equal 'Ada',                 contact.at_xpath('./Name/First').text
    assert_equal 'Lovelace',            contact.at_xpath('./Name/Last').text

    org = node.at_xpath('./Submission/Submission/Description/Organization')
    assert_equal 'owner',                    org['role']
    assert_equal 'center',                   org['type']
    assert_equal 'https://ddbj.nig.ac.jp',   org['url']
    assert_equal 'DDBJ',                     org.at_xpath('./Name').text
  end

  test 'rehydrates biology block from attribute bag (Strain + BiologicalProperties + Organization/Reproduction)' do
    record = {
      'project' => {
        'accession' => 'PRJDB000999',
        'organism'  => {'taxonomy_id' => 1234},
        'target'    => {'sample_scope' => 'eMonoisolate'},
        'attributes' => [
          {'name' => 'strain',                  'value' => 'K-12'},
          {'name' => 'gram_stain',              'value' => 'eNegative'},
          {'name' => 'oxygen_requirement',      'value' => 'eAerobe'},
          {'name' => 'biotic_relationship',     'value' => 'eFreeLiving'},
          {'name' => 'biological_organization', 'value' => 'eUnicellular'},
          {'name' => 'reproduction',            'value' => 'eAsexual'},
          {'name' => 'genome_size',             'value' => '4600000', 'unit' => 'bp'},
          {'name' => 'provider',                'value' => 'Some provider'}
        ]
      }
    }

    node = PublicXML::Bp::PackageRenderer.new(record:).call

    organism = node.at_xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism')
    assert_equal 'K-12',         organism.at_xpath('./Strain').text
    assert_equal 'eNegative',    organism.at_xpath('./BiologicalProperties/Morphology/Gram').text
    assert_equal 'eAerobe',      organism.at_xpath('./BiologicalProperties/Environment/OxygenReq').text
    assert_equal 'eFreeLiving',  organism.at_xpath('./BiologicalProperties/Phenotype/BioticRelationship').text
    assert_equal 'eUnicellular', organism.at_xpath('./Organization').text
    assert_equal 'eAsexual',     organism.at_xpath('./Reproduction').text

    genome_size = organism.at_xpath('./GenomeSize')
    assert_equal '4600000', genome_size.text
    assert_equal 'bp',      genome_size['units']

    provider = node.at_xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Target/Provider')
    assert_equal 'Some provider', provider.text
  end

  test 'rehydrates RepliconSet from indexed attribute bag tuples' do
    record = {
      'project' => {
        'accession' => 'PRJDB000888',
        'target'    => {},
        'organism'  => {},
        'attributes' => [
          {'name' => 'replicon_1_name',     'value' => 'chromosome'},
          {'name' => 'replicon_1_type',     'value' => 'eChromosome'},
          {'name' => 'replicon_1_location', 'value' => 'eNuclear'},
          {'name' => 'replicon_1_size',     'value' => '1234567', 'unit' => 'bp'},
          {'name' => 'replicon_2_name',     'value' => 'plasmid'},
          {'name' => 'replicon_2_type',     'value' => 'ePlasmid'},
          {'name' => 'ploidy',              'value' => 'eHaploid'}
        ]
      }
    }

    node      = PublicXML::Bp::PackageRenderer.new(record:).call
    replicons = node.xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/RepliconSet/Replicon')

    assert_equal 2, replicons.size
    assert_equal 'chromosome',  replicons[0].at_xpath('./Name').text
    assert_equal 'eChromosome', replicons[0].at_xpath('./Type').text
    assert_equal 'eNuclear',    replicons[0].at_xpath('./Type/@location').value
    assert_equal '1234567',     replicons[0].at_xpath('./Size').text
    assert_equal 'bp',          replicons[0].at_xpath('./Size/@units').value
    assert_equal 'plasmid',     replicons[1].at_xpath('./Name').text
    assert_equal 'ePlasmid',    replicons[1].at_xpath('./Type').text

    assert_equal 'eHaploid', node.at_xpath('./Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/RepliconSet/Ploidy/@type').value
  end

  test 'omits optional sections when not present in v3' do
    record = {
      'project' => {
        'accession' => 'PRJDB000001',
        'title'     => 'minimal'
      }
    }

    node = PublicXML::Bp::PackageRenderer.new(record:).call

    descr = node.at_xpath('./Project/Project/ProjectDescr')
    assert_not_nil descr.at_xpath('./Title')
    assert_nil     descr.at_xpath('./Description')
    assert_nil     descr.at_xpath('./Grant')
    assert_nil     descr.at_xpath('./Publication')
    assert_nil     descr.at_xpath('./Relevance')
    assert_nil     descr.at_xpath('./LocusTagPrefix')
    assert_nil     descr.at_xpath('./ProjectReleaseDate')

    assert_nil node.at_xpath('./Submission')
  end
end
