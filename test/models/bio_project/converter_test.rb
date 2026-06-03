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

  test 'PSUB000604 — Relevance is a dict of tag name → body text (v3 dict[str,str])' do
    assert_equal({'medical' => 'yes'}, convert.dig('project', 'relevance'))
  end

  test 'PSUB000604 — Target attrs + Method + ProjectDataTypeSet' do
    target = convert.dig('project', 'target')

    assert_equal 'eMonoisolate',        target['sample_scope']
    assert_equal 'eGenome',             target['material']
    assert_equal 'eWhole',              target['capture']
    assert_equal 'eSequencing',         target['method']
    assert_equal ['Genome Sequencing'], target['data_types']
  end

  test 'PSUB000604 — Submitters carry shared Organization (name + role + type)' do
    submitters = convert.dig('submission', 'submitters')

    expected_org = {
      'name' => 'Meijo University faculty of pharmacy',
      'role' => 'owner',
      'type' => 'center'
    }
    assert_equal 2, submitters.size
    assert_equal({'email' => 'sample-1@example.test', 'first' => 'Sample-First-1', 'last' => 'Sample-Last-1',
                  'organization' => expected_org},
                 submitters[0])
    assert_equal expected_org, submitters[1]['organization']
  end

  test 'PSUB002671 — Publication lifts pubmed_id + status (Reference body absent)' do
    pubs = convert(PSUB671_XML).dig('project', 'publications')

    assert_equal 1,             pubs.size
    assert_equal '23936076',    pubs[0]['pubmed_id']
    assert_equal 'ePublished',  pubs[0]['status']
    refute_includes pubs[0].keys, 'doi'
  end

  test 'PSUB002671 — Relevance Other (empty body) yields {"other" => ""}' do
    assert_equal({'other' => ''}, convert(PSUB671_XML).dig('project', 'relevance'))
  end

  test 'Relevance with body text on Other preserves the curator description' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectDescr>
          <Relevance><Other>Cancer cell line characterization</Other></Relevance>
        </ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    relevance = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                     .dig('project', 'relevance')

    assert_equal({'other' => 'Cancer cell line characterization'}, relevance)
  end

  test 'Publication: DbType nested inside Reference is recognised (eDOI → doi)' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectDescr>
          <Publication id="10.1000/foo" status="ePublished">
            <Reference><DbType>eDOI</DbType></Reference>
          </Publication>
        </ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    pubs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                .dig('project', 'publications')

    assert_equal 1, pubs.size
    assert_equal '10.1000/foo', pubs[0]['doi']
    assert_equal 'ePublished',  pubs[0]['status']
    refute_includes pubs[0].keys, 'pubmed_id'
  end

  test 'Publication: unknown DbType drops id (no silent mis-bind to pubmed_id)' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectDescr>
          <Publication id="some-isbn" status="ePublished">
            <DbType>eBookChapter</DbType>
          </Publication>
        </ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    pubs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                .dig('project', 'publications')

    assert_equal [{'status' => 'ePublished'}], pubs
  end

  test 'Organism: non-numeric taxID drops rather than becoming 0' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectType><ProjectTypeSubmission>
          <Target><Organism taxID="unknown"><OrganismName>foo</OrganismName></Organism></Target>
        </ProjectTypeSubmission></ProjectType>
      </Project></Project></Package></PackageSet>
    XML

    organism = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                    .dig('project', 'organism')

    assert_equal({'name' => 'foo'}, organism)
  end

  test 'Grant: empty <Title/> <Agency/> elements drop instead of becoming ""' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectDescr>
          <Grant GrantId="X1"><Title></Title><Agency abbr="NIH"></Agency></Grant>
        </ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    grants = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                  .dig('project', 'grants')

    assert_equal [{'id' => 'X1'}], grants
  end

  test 'canonicalises cleanly via the production pipeline' do
    bytes = DDBJRecord::Canonicalizer.canonicalize(convert)

    assert_kind_of String, bytes
    assert_includes bytes, '"accession":"PRJDB502"'
    assert_includes bytes, '"agency":"Japan Society for the Promotion of Science"'
  end

  test 'PSUB000604 — submission.hold_date lifts the date part of ProjectReleaseDate' do
    assert_equal '2013-05-30', convert.dig('submission', 'hold_date')
  end

  test 'hold_date: missing ProjectReleaseDate is omitted' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package>
        <Project><Project>
          <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
          <ProjectDescr/>
        </Project></Project>
        <Submission><Submission>
          <Description>
            <Organization role="owner" type="center">
              <Name>Org</Name>
              <Contact email="x@example.test"><Name><First>F</First><Last>L</Last></Name></Contact>
            </Organization>
          </Description>
        </Submission></Submission>
      </Package></PackageSet>
    XML

    submission = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                      .fetch('submission')

    refute_includes submission.keys, 'hold_date'
  end

  test 'hold_date: malformed ProjectReleaseDate drops silently' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package>
        <Project><Project>
          <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
          <ProjectDescr><ProjectReleaseDate>not-a-date</ProjectReleaseDate></ProjectDescr>
        </Project></Project>
        <Submission><Submission>
          <Description>
            <Organization role="owner" type="center">
              <Name>Org</Name>
              <Contact email="x@example.test"><Name><First>F</First><Last>L</Last></Name></Contact>
            </Organization>
          </Description>
        </Submission></Submission>
      </Package></PackageSet>
    XML

    submission = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                      .fetch('submission')

    refute_includes submission.keys, 'hold_date'
  end

  test 'PSUB000604 — project.attributes lifts strain' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'strain', 'value' => 'TH135'}
  end

  test 'PSUB000604 — project.attributes lifts the full Morphology block' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'gram_stain', 'value' => 'ePositive'}
    assert_includes attrs, {'name' => 'enveloped',  'value' => 'eNo'}
    assert_includes attrs, {'name' => 'shape',      'value' => 'eCocci'}
    assert_includes attrs, {'name' => 'endospores', 'value' => 'eNo'}
    assert_includes attrs, {'name' => 'motility',   'value' => 'eNo'}
  end

  test 'PSUB000604 — project.attributes lifts the full Environment block' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'salinity',            'value' => 'eMesophilic'}
    assert_includes attrs, {'name' => 'oxygen_requirement',  'value' => 'eAerobic'}
    assert_includes attrs, {'name' => 'optimum_temperature', 'value' => '37'}
    assert_includes attrs, {'name' => 'temperature_range',   'value' => 'eMesophilic'}
    assert_includes attrs, {'name' => 'habitat',             'value' => 'eMultiple'}
  end

  test 'PSUB000604 — project.attributes lifts the full Phenotype block' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'biotic_relationship', 'value' => 'eParasite'}
    assert_includes attrs, {'name' => 'trophic_level',       'value' => 'eAutotroph'}
    assert_includes attrs, {'name' => 'disease',             'value' => 'Mycobacterium avium complex disease'}
  end

  test 'PSUB000604 — project.attributes lifts Organization (multicellularity) and Reproduction' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'multicellularity', 'value' => 'eColonial'}
    assert_includes attrs, {'name' => 'reproduction',     'value' => 'eAsexual'}
  end

  test 'PSUB000604 — project.attributes lifts RepliconSet (Name, Type, Size with unit, Ploidy)' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'replicon_name', 'value' => 'plasmid'}
    assert_includes attrs, {'name' => 'replicon_type', 'value' => 'ePlasmid'}
    assert_includes attrs, {'name' => 'replicon_size', 'value' => '20', 'unit' => 'Kb'}
    assert_includes attrs, {'name' => 'ploidy',        'value' => 'eHaploid'}
  end

  test 'project.attributes: multiple Replicons each emit their own Name/Type/Size tuple' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectType><ProjectTypeSubmission>
          <Target sample_scope="eMonoisolate" material="eGenome" capture="eWhole">
            <Organism taxID="1">
              <OrganismName>foo</OrganismName>
              <RepliconSet>
                <Replicon><Name>chr1</Name><Type>eChromosome</Type><Size units="Mb">3</Size></Replicon>
                <Replicon><Name>chr2</Name><Type>eChromosome</Type><Size units="Mb">2</Size></Replicon>
              </RepliconSet>
            </Organism>
          </Target>
        </ProjectTypeSubmission></ProjectType>
      </Project></Project></Package></PackageSet>
    XML

    attrs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                 .dig('project', 'attributes')

    replicon_names = attrs.select {|a| a['name'] == 'replicon_name' }.map {|a| a['value'] }
    replicon_sizes = attrs.select {|a| a['name'] == 'replicon_size' }

    assert_equal ['chr1', 'chr2'], replicon_names
    assert_equal 2, replicon_sizes.size
    assert_equal({'name' => 'replicon_size', 'value' => '3', 'unit' => 'Mb'}, replicon_sizes[0])
    assert_equal({'name' => 'replicon_size', 'value' => '2', 'unit' => 'Mb'}, replicon_sizes[1])
  end

  test 'PSUB000604 — project.attributes lifts GenomeSize with unit' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'genome_size', 'value' => '5', 'unit' => 'Mb'}
  end

  test 'project.attributes: GenomeSize without @units omits the unit key' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectType><ProjectTypeSubmission>
          <Target sample_scope="eMonoisolate" material="eGenome" capture="eWhole">
            <Organism taxID="1">
              <OrganismName>foo</OrganismName>
              <GenomeSize>5000000</GenomeSize>
            </Organism>
          </Target>
        </ProjectTypeSubmission></ProjectType>
      </Project></Project></Package></PackageSet>
    XML

    attrs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                 .dig('project', 'attributes')

    assert_equal [{'name' => 'genome_size', 'value' => '5000000'}], attrs
  end

  test 'PSUB000604 — project.attributes lifts Provider' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'provider', 'value' => 'Higashinagoya National Hospital'}
  end

  test 'project.attributes: omitted entirely when no biology block is present' do
    project = convert(PSUB671_XML).fetch('project')

    refute_includes project.keys, 'attributes'
  end

  test 'project.attributes: blank Strain/Morphology values drop' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectType><ProjectTypeSubmission>
          <Target sample_scope="eMonoisolate" material="eGenome" capture="eWhole">
            <Organism taxID="1">
              <OrganismName>foo</OrganismName>
              <Strain></Strain>
              <BiologicalProperties>
                <Morphology><Gram>   </Gram><Shape>eRod</Shape></Morphology>
              </BiologicalProperties>
            </Organism>
          </Target>
        </ProjectTypeSubmission></ProjectType>
      </Project></Project></Package></PackageSet>
    XML

    attrs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                 .dig('project', 'attributes')

    assert_equal [{'name' => 'shape', 'value' => 'eRod'}], attrs
  end
end
