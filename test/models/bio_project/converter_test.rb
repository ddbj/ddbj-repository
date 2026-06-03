require 'test_helper'

class BioProject::ConverterTest < ActiveSupport::TestCase
  PSUB604_XML = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB000604.xml').freeze
  PSUB671_XML = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB002671.xml').freeze

  def convert(path = PSUB604_XML, project_type: 'primary')
    BioProject::Converter.new(xml: File.read(path), project_row: {project_type:}).call
  end

  test 'project_row[:accession] wins over XML <ArchiveID> (DB column is source of truth)' do
    # Staging-observed pathology: XML <ArchiveID accession="PSUB..."> carries
    # the PSUB id instead of the canonical PRJDB. The DB column
    # project.project_id_prefix || project_id_counter holds the real
    # accession. When the caller passes it, Converter must prefer it.
    record = BioProject::Converter.new(
      xml:         File.read(PSUB604_XML),
      project_row: {project_type: 'primary', accession: 'PRJDB9999999'}
    ).call

    assert_equal 'PRJDB9999999', record.dig('project', 'accession'),
                 'DB-column accession must override the XML ArchiveID'
  end

  test 'project_row without :accession (or with nil) falls back to XML ArchiveID' do
    # File-based importer path: only XML is available, no staging row.
    # Existing behaviour preserved — XML serves as the fallback.
    record_no_key  = BioProject::Converter.new(xml: File.read(PSUB604_XML), project_row: {project_type: 'primary'}).call
    record_nil_key = BioProject::Converter.new(xml: File.read(PSUB604_XML), project_row: {project_type: 'primary', accession: nil}).call

    assert_equal 'PRJDB502', record_no_key.dig('project', 'accession')
    assert_equal 'PRJDB502', record_nil_key.dig('project', 'accession')
  end

  test 'DB present + XML <ArchiveID/> empty → DB wins (headline production-win cohort)' do
    # Production has ~17/43,372 rows where the XML carries an empty
    # <ArchiveID/> but the DB has a valid PRJDB. Pre-change those flowed
    # as :no_accession; post-change they flow as :created with the DB
    # value. Pin the precedence so a future refactor that drops .presence
    # from the XML side (silently short-circuiting on '') can't regress
    # them.
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet>
        <Package>
          <Project><Project>
            <ProjectID><ArchiveID accession=""/></ProjectID>
            <ProjectType><ProjectTypeSubmission>
              <Target/>
            </ProjectTypeSubmission></ProjectType>
            <ProjectDescr><Title>t</Title></ProjectDescr>
          </Project></Project>
        </Package>
      </PackageSet>
    XML

    record = BioProject::Converter.new(xml:, project_row: {project_type: 'primary', accession: 'PRJDB7777777'}).call
    assert_equal 'PRJDB7777777', record.dig('project', 'accession')
  end

  test 'staging PSUB-id-in-ArchiveID pathology: DB wins, PSUB id in XML is discarded' do
    # The exact 2,383-row staging pathology that motivated this commit:
    # XML <ArchiveID accession="PSUB990415"> carries a PSUB id (NOT a
    # PRJDB accession). The DB column holds the canonical PRJDB. Pin
    # the recovery contract directly with the pathological shape so
    # future readers see the bug being prevented.
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet>
        <Package>
          <Project><Project>
            <ProjectID><ArchiveID accession="PSUB990415"/></ProjectID>
            <ProjectType><ProjectTypeSubmission>
              <Target/>
            </ProjectTypeSubmission></ProjectType>
            <ProjectDescr><Title>t</Title></ProjectDescr>
          </Project></Project>
        </Package>
      </PackageSet>
    XML

    record = BioProject::Converter.new(xml:, project_row: {project_type: 'primary', accession: 'PRJDB3723'}).call
    assert_equal 'PRJDB3723', record.dig('project', 'accession')
  end

  test 'whitespace in accession is stripped (matches Project::ACCESSION_FORMAT anchored regex)' do
    # Defence in depth: both DB and XML paths use &.strip&.presence so
    # a value like 'PRJDB123 ' (trailing space — however it might end
    # up there) does not bypass Project's anchored format validator.
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession=""/></ProjectID>
        <ProjectType><ProjectTypeSubmission><Target/></ProjectTypeSubmission></ProjectType>
        <ProjectDescr><Title>t</Title></ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    record = BioProject::Converter.new(xml:, project_row: {project_type: 'primary', accession: '  PRJDB42  '}).call
    assert_equal 'PRJDB42', record.dig('project', 'accession')
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

  test 'submission.hold_date strict parsing: partial / month-name / day-only inputs drop instead of fabricating dates' do
    %w[May Jan 12 abc].each do |bad|
      xml = <<~XML
        <?xml version="1.0"?>
        <PackageSet><Package><Project><Project>
          <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
          <ProjectDescr><ProjectReleaseDate>#{bad}</ProjectReleaseDate></ProjectDescr>
        </Project></Project></Package></PackageSet>
      XML

      hold = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                  .dig('submission', 'hold_date')

      assert_nil hold, "expected hold_date to drop on #{bad.inspect}, got #{hold.inspect}"
    end
  end

  test 'submission.hold_date survives even when no <Submission><Submission> element exists' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectDescr><ProjectReleaseDate>2024-02-29T00:00:00+09:00</ProjectReleaseDate></ProjectDescr>
      </Project></Project></Package></PackageSet>
    XML

    record = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
    assert_equal '2024-02-29', record.dig('submission', 'hold_date')
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

  test 'PSUB000604 — project.attributes lifts Organization (biological_organization) and Reproduction' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'biological_organization', 'value' => 'eColonial'}
    assert_includes attrs, {'name' => 'reproduction',            'value' => 'eAsexual'}
  end

  test 'PSUB000604 — project.attributes lifts RepliconSet (per-replicon index, location, isSingle, Ploidy)' do
    attrs = convert.dig('project', 'attributes')

    assert_includes attrs, {'name' => 'replicon_1_name',      'value' => 'plasmid'}
    assert_includes attrs, {'name' => 'replicon_1_type',      'value' => 'ePlasmid'}
    assert_includes attrs, {'name' => 'replicon_1_location',  'value' => 'eNuclearProkaryote'}
    assert_includes attrs, {'name' => 'replicon_1_is_single', 'value' => 'false'}
    assert_includes attrs, {'name' => 'replicon_1_size',      'value' => '20', 'unit' => 'Kb'}
    assert_includes attrs, {'name' => 'ploidy',               'value' => 'eHaploid'}
  end

  test 'project.attributes: multiple Replicons are unambiguously grouped by index even with mixed missing fields' do
    xml = <<~XML
      <?xml version="1.0"?>
      <PackageSet><Package><Project><Project>
        <ProjectID><ArchiveID accession="PRJDB999"/></ProjectID>
        <ProjectType><ProjectTypeSubmission>
          <Target sample_scope="eMonoisolate" material="eGenome" capture="eWhole">
            <Organism taxID="1">
              <OrganismName>foo</OrganismName>
              <RepliconSet>
                <Replicon><Type location="eMitochondrion">eChromosome</Type><Size units="Mb">3</Size></Replicon>
                <Replicon><Name>chr2</Name><Type location="eNuclearProkaryote">eChromosome</Type><Size units="Mb">2</Size></Replicon>
              </RepliconSet>
            </Organism>
          </Target>
        </ProjectTypeSubmission></ProjectType>
      </Project></Project></Package></PackageSet>
    XML

    attrs = BioProject::Converter.new(xml: xml, project_row: {project_type: 'primary'}).call
                                 .dig('project', 'attributes')

    # First Replicon: no name, but type + location + size by index 1.
    assert_includes attrs, {'name' => 'replicon_1_type',     'value' => 'eChromosome'}
    assert_includes attrs, {'name' => 'replicon_1_location', 'value' => 'eMitochondrion'}
    assert_includes attrs, {'name' => 'replicon_1_size',     'value' => '3', 'unit' => 'Mb'}
    refute_includes attrs.map {|a| a['name'] }, 'replicon_1_name'

    # Second Replicon: full triple under index 2.
    assert_includes attrs, {'name' => 'replicon_2_name',     'value' => 'chr2'}
    assert_includes attrs, {'name' => 'replicon_2_type',     'value' => 'eChromosome'}
    assert_includes attrs, {'name' => 'replicon_2_location', 'value' => 'eNuclearProkaryote'}
    assert_includes attrs, {'name' => 'replicon_2_size',     'value' => '2', 'unit' => 'Mb'}
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
