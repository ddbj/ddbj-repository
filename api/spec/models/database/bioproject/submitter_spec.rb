require 'rails_helper'

RSpec.describe Database::BioProject::Submitter do
  def create_submission(visibility:)
    create(:submission, **{
      visibility:,

      validation: build(:validation, :valid, **{
        user:,

        objs: [
          build(:obj, **{
            _id:      'BioProject',
            file:     file_fixture('bioproject/valid/1_not_well_format_xml_ok.xml'),
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

  example 'visibility: private' do
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

    expect(Dway.bioproject[:submission_data]).to contain_exactly(
      include(
        submission_id: 'PSUB000001',
        data_name:     'first_name',
        data_value:    'Alice',
        form_name:     'submitter',
        t_order:       1
      ),
      include(
        submission_id: 'PSUB000001',
        data_name:     'last_name',
        data_value:    'Liddell',
        form_name:     'submitter',
        t_order:       2
      ),
      include(
        submission_id: 'PSUB000001',
        data_name:     'email',
        data_value:    'alice@example.com',
        form_name:     'submitter',
        t_order:       3
      ),
      include(
        submission_id: 'PSUB000001',
        data_name:     'organization_name',
        data_value:    'Rabbit Hole, Wonderland Inc.',
        form_name:     'submitter',
        t_order:       4
      ),
      include(
        submission_id: 'PSUB000001',
        data_name:     'organization_url',
        data_value:    'http://wonderland.example.com',
        form_name:     'submitter',
        t_order:       5
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
end
