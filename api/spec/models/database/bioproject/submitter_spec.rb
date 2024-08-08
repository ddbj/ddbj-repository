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
        t_order:       1
      ),
      include(
        form_name:  'general_info',
        data_name:  'public_description',
        data_value: 'Description text',
        t_order:    2
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
    
    expect(Dway.bioproject[:submission_data].to_a).to include(
      include(
        form_name:  'general_info',
        data_name:  'project_title',
        data_value: 'general_info.project_title'
      ),
      include(
        form_name:  'general_info',
        data_name:  'public_description',
        data_value: 'general_info.public_description'
      ),
      include(
        form_name:  'general_info',
        data_name:  'link_url.1',
        data_value: 'general_info.link_uri.i'
      ),
      include(
        form_name:  'general_info',
        data_name:  'link_description.1',
        data_value: 'general_info.link_description.i'
      ),
      include(
        form_name:  'general_info',
        data_name:  'link_url.2',
        data_value: 'general_info.link_uri.j'
      ),
      include(
        form_name:  'general_info',
        data_name:  'link_description.2',
        data_value: 'general_info.link_description.j'
      ),
    )
  end
end
