require 'rails_helper'

RSpec.describe Database::BioProject::Submitter do
  def create_submission(visibility:, file:)
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

  let(:user) { create(:user, uid: 'alice') }

  example 'submit' do
    travel_to '2024-01-02 12:34:56'
    
    submission = create_submission(visibility: :private, file: 'bioproject/valid/hup.xml')

    Database::BioProject::Submitter.new.submit submission

    expect(BioProject::Submission.sole).to have_attributes(
      submission_id:     'PSUB000001',
      submitter_id:      'alice',
      status_id:         'data_submitted',
      form_status_flags: ''
    )

    expect(BioProject::Project.sole).to have_attributes(
      submission_id: 'PSUB000001',
      project_type:  'primary',
      status_id:     'private',
      release_date:  nil,
      dist_date:     nil,
      modified_date: '2024-01-02 12:34:56'.to_time
    )

    expect(BioProject::XML.sole).to have_attributes(
      submission_id:   'PSUB000001',
      content:         instance_of(String),
      version:         1,
      registered_date: '2024-01-02 12:34:56 +0900'
    )

    doc        = Nokogiri::XML.parse(BioProject::XML.sole.content)
    archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')

    expect(archive_id[:accession]).to eq('PSUB000001')
    expect(archive_id[:archive]).to eq('DDBJ')

    expect(BioProject::ActionHistory.sole).to have_attributes(
      submission_id: 'PSUB000001',
      action:        '[repository:CreateNewSubmission] Create new submission',
      action_date:   '2024-01-02 12:34:56'.to_time,
      result:        true,
      action_level:  'info',
      submitter_id:  'alice'
    )

    ext_entity = DRMDB::ExtEntity.sole

    expect(ext_entity).to have_attributes(
      ext_id:   instance_of(Integer),
      acc_type: 'study',
      ref_name: 'PSUB000001',
      status:   'valid'
    )

    expect(DRMDB::ExtPermit.sole).to have_attributes(
      ext_id:       ext_entity.ext_id,
      submitter_id: 'alice'
    )

    expect(BioProject::SubmissionDatum.all).to include(
      have_attributes(
        submission_id: 'PSUB000001',
        form_name:     'general_info',
        data_name:     'project_title',
        data_value:    'Title text',
        t_order:       -1
      ),
      have_attributes(
        submission_id: 'PSUB000001',
        form_name:     'general_info',
        data_name:     'public_description',
        data_value:    'Description text',
        t_order:       -1
      )
    )
  end

  example 'visibility: public' do
    travel_to '2024-01-02 12:34:56'

    submission = create_submission(visibility: :public, file: 'bioproject/valid/nonhup.xml')

    Database::BioProject::Submitter.new.submit submission

    expect(BioProject::Project.sole).to have_attributes(
      submission_id: 'PSUB000001',
      project_type:  'primary',
      status_id:     'public',
      release_date:  '2024-01-02 12:34:56'.to_time,
      dist_date:     '2024-01-02 12:34:56'.to_time,
      modified_date: '2024-01-02 12:34:56'.to_time
    )
  end

  example 'full' do
    submission = create_submission(visibility: :private, file: 'bioproject/valid/full.xml')

    Database::BioProject::Submitter.new.submit submission

    expect(BioProject::SubmissionDatum.all.map { _1.slice(:form_name, :data_name, :data_value, :t_order).symbolize_keys }).to eq([
      {
        form_name:  'submitter',
        data_name:  'first_name.1',
        data_value: 'submitter.first_name.1?',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'last_name.1',
        data_value: 'submitter.last_name.1',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'email.1',
        data_value: 'submitter.email.1?',
        t_order:    1
      },
      {
        form_name:  'submitter',
        data_name:  'first_name.2',
        data_value: 'submitter.first_name.2?',
        t_order:    2
      },
      {
        form_name:  'submitter',
        data_name:  'last_name.2',
        data_value: 'submitter.last_name.2',
        t_order:    2
      },
      {
        form_name:  'submitter',
        data_name:  'email.2',
        data_value: 'submitter.email.2?',
        t_order:    2
      },
      {
        form_name:  'submitter',
        data_name:  'organization_name',
        data_value: 'submitter.organization_name',
        t_order:    -1
      },
      {
        form_name:  'submitter',
        data_name:  'organization_url',
        data_value: 'submitter.organization_url?',
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
        data_name:  'link_description.1',
        data_value: 'general_info.link_description.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'link_url.1',
        data_value: 'general_info.link_uri.1',
        t_order:    1
      },
      {
        form_name:  'general_info',
        data_name:  'link_description.2',
        data_value: 'general_info.link_description.2',
        t_order:    2
      },
      {
        form_name:  'general_info',
        data_name:  'link_url.2',
        data_value: 'general_info.link_uri.2',
        t_order:    2
      },
      {
        form_name:  'general_info',
        data_name:  'agency.1',
        data_value: 'general_info.agency.1',
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
        form_name:  'project_type',
        data_name:  'project_data_type',
        data_value: 'genome_sequencing',
        t_order:    1
      },
      {
        form_name:  'project_type',
        data_name:  'project_data_type',
        data_value: 'other',
        t_order:    2
      },
      {
        form_name:  'project_type',
        data_name:  'project_data_type_description',
        data_value: 'project_type.project_data_type_description.2',
        t_order:    2
      },
      {
        form_name:  'project_type',
        data_name:  'sample_scope',
        data_value: 'project_type.sample_scope',
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
        form_name:  'target',
        data_name:  'organism_name',
        data_value: 'target.organism_name',
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
        data_name:  'strain_breed_cultivar',
        data_value: 'target.strain_breed_cultivar',
        t_order:    -1
      },
      {
        form_name:  'target',
        data_name:  'isolate_name_or_label',
        data_value: 'target.isolate_name_or_label?',
        t_order:    -1
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
    ])
  end

  example 'submission id is overflow' do
    travel_to '2024-01-02 12:34:56'

    BioProject::Submission.create! submission_id: 'PSUB999999', submitter_id: user.uid

    expect {
      Database::BioProject::Submitter.new.submit create_submission(visibility: :private, file: 'bioproject/valid/hup.xml')
    }.to raise_error(Database::BioProject::Submitter::SubmissionIDOverflow)

    expect(BioProject::Submission.count).to eq(1)

    expect(BioProject::ActionHistory.sole).to have_attributes(
      submission_id: nil,
      action:        '[repository:CreateNewSubmission] Number of submission surpass the upper limit',
      action_date:   '2024-01-02 12:34:56'.to_time,
      result:        false,
      action_level:  'fatal',
      submitter_id:  'alice'
    )
  end

  example 'visibility is public and hold exist' do
    travel_to '2024-01-02 12:34:56'

    expect {
      Database::BioProject::Submitter.new.submit create_submission(visibility: :public, file: 'bioproject/valid/hup.xml')
    }.to raise_error(Database::BioProject::Submitter::VisibilityMismatch, 'Visibility is public, but Hold exist in XML.')

    expect(BioProject::Submission.count).to eq(0)

    expect(BioProject::ActionHistory.sole).to have_attributes(
      submission_id: nil,
      action:        '[repository:CreateNewSubmission] rollback transaction',
      action_date:   '2024-01-02 12:34:56'.to_time,
      result:        false,
      action_level:  'error',
      submitter_id:  'alice'
    )
  end

  example 'visibility is private and hold does not exist' do
    expect {
      Database::BioProject::Submitter.new.submit create_submission(visibility: :private, file: 'bioproject/valid/nonhup.xml')
    }.to raise_error(Database::BioProject::Submitter::VisibilityMismatch, 'Visibility is private, but Hold does not exist in XML.')
  end
end
