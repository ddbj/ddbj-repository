require 'rails_helper'

RSpec.describe Database::BioProject::Submitter do
  def create_submission(visibility: :private, file: 'bioproject/valid/1_not_well_format_xml_ok.xml')
    create(:submission, **{
      visibility:,

      validation: build(:validation, :valid, **{
        user:,

        objs: [
          build(:obj, **{
            _id:      'BioProject',
            file:     file_fixture(file),
            validity: :valid
          })
        ]
      })
    })
  end

  let(:user) {
    create(:user, **{
      uid:              'alice',
      email:            'alice@example.com',
      first_name:       'Alice',
      last_name:        'Liddell',
      organization:     'Wonderland Inc.',
      department:       'Rabbit Hole',
      organization_url: 'http://wonderland.example.com'
    })
  }

  example 'submit' do
    submission = create_submission(visibility: :private)

    Database::BioProject::Submitter.new.submit submission

    expect(Dway.bioproject[:submission].first).to include(
      submission_id:     'PSUB000001',
      submitter_id:      'alice',
      status_id:         Database::BioProject::Submitter::BP_SUBMISSION_STATUS_ID_DATA_SUBMITTED,
      form_status_flags: ''
    )

    expect(Dway.bioproject[:project].first).to include(
      submission_id: 'PSUB000001',
      project_type:  'primary',
      status_id:     Database::BioProject::Submitter::BP_PROJECT_STATUS_ID_PRIVATE,
      release_date:  nil,
      dist_date:     nil,
      modified_date: instance_of(Time)
    )

    expect(Dway.bioproject[:xml].first).to include(
      submission_id:   'PSUB000001',
      content:         instance_of(String),
      version:         1,
      registered_date: instance_of(String)
    )

    doc        = Nokogiri::XML.parse(Dway.bioproject[:xml].first[:content])
    archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')

    expect(archive_id[:accession]).to eq('PSUB000001')
    expect(archive_id[:archive]).to eq('DDBJ')

    ext_entity = Dway.drmdb[:ext_entity].first

    expect(ext_entity).to include(
      ext_id:   instance_of(Integer),
      acc_type: Database::BioProject::Submitter::SCHEMA_TYPE_STUDY.to_s,
      ref_name: 'PSUB000001',
      status:   Database::BioProject::Submitter::EXT_STATUS_VALID
    )

    expect(Dway.drmdb[:ext_permit].first).to include(
      ext_id:       ext_entity[:ext_id],
      submitter_id: 'alice'
    )

    expect(Dway.bioproject[:submission_data]).to include(
      include(
        submission_id: 'PSUB000001',
        form_name:     'general_info',
        data_name:     'project_title',
        data_value:    'Title text',
        t_order:       -1
      ),
      include(
        submission_id: 'PSUB000001',
        form_name:     'general_info',
        data_name:     'public_description',
        data_value:    'Description text',
        t_order:       -1
      )
    )
  end

  example 'visibility: public' do
    submission = create_submission(visibility: :public)

    Database::BioProject::Submitter.new.submit submission

    expect(Dway.bioproject[:project].first).to include(
      submission_id: 'PSUB000001',
      project_type:  'primary',
      status_id:     Database::BioProject::Submitter::BP_PROJECT_STATUS_ID_PUBLIC,
      release_date:  instance_of(Time),
      dist_date:     instance_of(Time),
      modified_date: instance_of(Time)
    )
  end

  example 'full' do
    submission = create_submission(file: 'bioproject/valid/full.xml')

    Database::BioProject::Submitter.new.submit submission

    expect(Dway.bioproject[:submission_data].map { _1.slice(:form_name, :data_name, :data_value, :t_order) }).to include(
      {
        form_name:  'submitter',
        data_name:  'first_name',
        data_value: 'Alice',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'last_name',
        data_value: 'Liddell',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'email',
        data_value: 'alice@example.com',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'organization_name',
        data_value: 'Rabbit Hole, Wonderland Inc.',
        t_order:    -1
      },
      {
        form_name:  'submitter',
        data_name:  'organization_url',
        data_value: 'http://wonderland.example.com',
        t_order:    -1
      },
      {
        form_name:  'submitter',
        data_name:  'data_release',
        data_value: 'hup',
        t_order:    -1
      },
      {
        form_name:  'general_info',
        data_name:  'project_title',
        data_value: 'general_info.project_title',
        t_order:    -1
      },
      {
        form_name:  'general_info',
        data_name:  'public_description',
        data_value: 'general_info.public_description',
        t_order:    -1
      },
      {
        form_name:  'general_info',
        data_name:  'link_url.1',
        data_value: 'general_info.link_uri.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'link_description.1',
        data_value: 'general_info.link_description.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'link_url.2',
        data_value: 'general_info.link_uri.2',
        t_order:    2
      },
      {
        form_name:  'general_info',
        data_name:  'link_description.2',
        data_value: 'general_info.link_description.2',
        t_order:    2
      },
      {
        form_name:  'general_info',
        data_name:  'grant_id.1',
        data_value: 'general_info.grant_id.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'grant_title.1',
        data_value: 'general_info.grant_title.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'agency_abbreviation.1',
        data_value: 'general_info.agency_abbreviation.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'agency.1',
        data_value: 'general_info.agency.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'relevance_description',
        data_value: 'general_info.relevance_description',
        t_order:    -1
      },
      {
        form_name:  'general_info',
        data_name:  'biomaterial_provider',
        data_value: 'general_info.biomaterial_provider?',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'locus_tag',
        data_value: 'project_type.locus_tag',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'sample_code',
        data_value: 'project_type.sample_code',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'material',
        data_value: 'project_type.material',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'capture',
        data_value: 'project_type.capture',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'taxonomy_id',
        data_value: 'target.taxonomy_id || 0',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'organism_name',
        data_value: 'target.organism_name',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'isolate_name_or_label',
        data_value: 'target.isolate_name_or_label?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'strain_breed_cultivar',
        data_value: 'target.strain_breed_cultivar',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'prokaryote_gram',
        data_value: 'target.prokaryote_gram?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'prokaryote_enveloped',
        data_value: 'target.prokaryote_enveloped?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'prokaryote_shape.1',
        data_value: 'target.prokaryote_shape.1*',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'prokaryote_endospores',
        data_value: 'target.prokaryote_endospores?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'prokaryote_motility',
        data_value: 'target.prokaryote_motility?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'environment_salinity',
        data_value: 'target.environment_salinity?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'environment_oxygen_requirement',
        data_value: 'target.environment_oxygen_requirement?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'environment_optimum_temperature',
        data_value: 'target.environment_optimum_temperature?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'environment_temperature_range',
        data_value: 'target.environment_temperature_range?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'environment_habitat',
        data_value: 'target.environment_habitat?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'phenotype_biotic_relationship',
        data_value: 'target.phenotype_biotic_relationship?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'phenotype_trophic_level',
        data_value: 'target.phenotype_trophic_level?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'phenotype_disease',
        data_value: 'target.phenotype_disease?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'cellularity',
        data_value: 'target.cellularity?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'reproduction',
        data_value: 'target.reproduction?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'replicons_order.1',
        data_value: 'target.replicons_order.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_location.1',
        data_value: 'target.replicons_location.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_type_description.1',
        data_value: 'target.replicons_type_description.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_location_description.1',
        data_value: 'target.replicons_location_description.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_type.1',
        data_value: 'target.replicons_type.1',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_name.1',
        data_value: 'target.replicons_name.1',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_size_unit.1',
        data_value: 'target.replicons_size_unit.1',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_size.1',
        data_value: 'target.replicons_size.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'replicons_description.1',
        data_value: 'target.replicons_description.1?',
        t_order:    1
      },
      {
        form_name:  'target',
        data_name:  'ploidy',
        data_value: 'target.ploidy?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'haploid_genome_size_unit',
        data_value: 'target.haploid_genome_size_unit',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'haploid_genome_size',
        data_value: 'target.haploid_genome_size?',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'label_description',
        data_value: 'target.label_description?',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'methodology',
        data_value: 'project_type.methodology',
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'methodology_description',
        data_value: nil,
        t_order:    -1
      },
      {
        form_name:  'project_type',
        data_name:  'objective.1',
        data_value: 'project_type.objective.1*',
        t_order:    1
      },
      {
        form_name:  'publication',
        data_name:  'pubmed_id.1',
        data_value: 'publication.pubmed_id.1',
        t_order:    1
      },
      {
        form_name:  'publication',
        data_name:  'doi.2',
        data_value: 'publication.doi.2',
        t_order:    2
      }
    )
  end
end
