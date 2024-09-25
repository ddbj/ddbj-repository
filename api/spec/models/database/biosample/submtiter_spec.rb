require 'rails_helper'

RSpec.describe Database::BioSample::Submitter do
  def create_submission(file)
    create(:submission, **{
      validation: build(:validation, :valid, **{
        user:,

        objs: [
          build(:obj, **{
            _id:      'BioSample',
            file:,
            validity: :valid
          })
        ]
      })
    })
  end

  let(:user) { create(:user, uid: 'alice') }

  before do
    stub_request(:get, 'validator.example.com/api/package_group_list').to_return_json(
      body: [
        {
          package_group_uri:  "http://ddbj.nig.ac.jp/ontologies/biosample/MIxS_PackageGroup",
          package_group_id:   "MIxS",
          package_group_name: "Genome, metagenome or marker sequences (MIxS compliant)",
          type:               "package_group",
          package_list: [
            {
              package_group_uri:        "http://ddbj.nig.ac.jp/ontologies/biosample/MIGS.ba_PackageGroup",
              package_group_id:         "MIGS.ba",
              package_group_name:       "Cultured Bacterial/Archaeal Genomic Sequences (MIGS)",
              parent_package_group_uri: "http://ddbj.nig.ac.jp/ontologies/biosample/MIxS_PackageGroup",
              type:                     "package_group",
              package_list: [
                {
                  package_uri:                "http://ddbj.nig.ac.jp/ontologies/biosample/MIGS.ba.microbial_Package",
                  package_id:                 "MIGS.ba.microbial",
                  version:                    "5.0",
                  package_name:               "MIGS: cultured bacteria/archaea, microbial mat/biofilm; version 5.0",
                  env_package:                "microbial mat/biofilm",
                  parent_package_group_uri:   "http://ddbj.nig.ac.jp/ontologies/biosample/MIGS.ba_PackageGroup",
                  parent_package_grounp_name: "Cultured Bacterial/Archaeal Genomic Sequences (MIGS)",
                  type:                       "package"
                }
              ]
            }
          ]
        }
      ]
    )
  end

  example 'submit' do
    travel_to '2024-01-02 12:34:56'

    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok.xml'))

    Database::BioSample::Submitter.new.submit submission

    attribute_file = {
      sample_name:       'MTB313',
      strain:            'MTB313',
      env_biome:         'urban biome',
      collection_date:   '2011-12-01T01:02:03Z',
      env_feature:       'town',
      geo_loc_name:      'Japan:Hikone-shi',
      lat_lon:           '35.262246 N 136.225389 E',
      env_material:      'interstitial fluid',
      project_name:      'Streptococcus pyogenes MTB313 genome sequencing',
      isol_growth_condt: '24464696',
      num_replicons:     '1',
      ref_biomaterial:   '16088826',
      elev:              '88.8m',
      depth:             '0m',
      bioproject_id:     'PRJDB1654',
      env_broad_scale:   'missing',
      env_local_scale:   'missing',
      env_medium:        'missing'
    }.to_a.transpose.map { _1.join("\t") + "\n" }.join

    expect(BioSample::SubmissionForm.sole).to have_attributes(
      submission_id:       'SSUB000001',
      submitter_id:        'alice',
      status_id:           'new',
      organization:        'Kitasato Institute of Life Sciences',
      organization_url:    'https://www.kitasato-u.ac.jp/lisci/',
      release_type:        'release',
      attribute_file_name: 'SSUB000001.tsv',
      attribute_file:,
      comment:             nil,
      package_group:       'MIGS.ba',
      package:             'MIGS.ba.microbial',
      env_package:         'microbial mat/biofilm'
    )

    expect(BioSample::Submission.sole).to have_attributes(
      submission_id:    'SSUB000001',
      submitter_id:     'alice',
      organization:     'Kitasato Institute of Life Sciences',
      organization_url: 'https://www.kitasato-u.ac.jp/lisci/',
      charge_id:        1
    )

    expect(BioSample::ContactForm.sole).to have_attributes(
      submission_id: 'SSUB000001',
      first_name:    'Haruno',
      last_name:     'Yoshida',
      email:         'harunoy@lisci.kitasato-u.ac.jp.ddbj.test',
      seq_no:        1
    )

    expect(BioSample::Contact.sole).to have_attributes(
      submission_id: 'SSUB000001',
      first_name:    'Haruno',
      last_name:     'Yoshida',
      email:         'harunoy@lisci.kitasato-u.ac.jp.ddbj.test',
      seq_no:        1
    )

    expect(BioSample::LinkForm.sole).to have_attributes(
      description:   'Example',
      url:           'http://example.com',
      submission_id: 'SSUB000001',
      seq_no:        1
    )

    sample = BioSample::Sample.sole

    expect(sample).to have_attributes(
      submission_id: 'SSUB000001',
      sample_name:   'MTB313',
      release_type:  'release',
      release_date:  nil,
      package_group: 'MIGS.ba',
      package:       'MIGS.ba.microbial',
      env_package:   'microbial mat/biofilm',
      status_id:     'submission_accepted'
    )

    expect(sample._attributes.count).to eq(18)

    expect(sample._attributes).to include(
      have_attributes(
        attribute_name:  'sample_name',
        attribute_value: 'MTB313',
        seq_no:          1
      ),
      have_attributes(
        attribute_name:  'env_medium',
        attribute_value: 'missing',
        seq_no:          18
      )
    )

    expect(sample.links.sole).to have_attributes(
      description: 'Example',
      url:         'http://example.com',
      seq_no:      1
    )

    xml = sample.xmls.sole

    expect(xml).to have_attributes(
      version: 1,
      content: instance_of(String)
    )

    expect(Nokogiri::XML.parse(xml.content).at('/BioSample/Description/SampleName').text).to eq('MTB313')

    expect(BioSample::OperationHistory.sole).to have_attributes(
      type:          'info',
      summary:       '[repository:CreateNewSubmission] Create new submission',
      date:          '2024-01-02 12:34:56'.to_time,
      submitter_id:  'alice',
      submission_id: 'SSUB000001'
    )

    ext_entity = DRMDB::ExtEntity.sole

    expect(ext_entity).to have_attributes(
      acc_type: 'sample',
      ref_name: sample.id.to_s,
      status:   'valid'
    )

    expect(DRMDB::ExtPermit.sole).to have_attributes(
      ext_id:       ext_entity.ext_id,
      submitter_id: 'alice'
    )
  end

  example 'two BioSample, valid' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_two_biosamples.xml'))

    Database::BioSample::Submitter.new.submit submission

    expect(BioSample::SubmissionForm.sole.attribute_file).to eq(<<~TSV)
      sample_name	strain	env_biome
      MTB313	MTB313	urban biome
      MTB314	MTB314	urban biome
    TSV

    samples = BioSample::Sample.order(:smp_id)

    expect(samples.count).to eq(2)

    expect(samples.first).to have_attributes(
      submission_id: 'SSUB000001',
      sample_name:   'MTB313',
      release_type:  'release',
      release_date:  nil,
      package_group: 'MIGS.ba',
      package:       'MIGS.ba.microbial',
      env_package:   'microbial mat/biofilm',
      status_id:     'submission_accepted'
    )

    expect(samples.first._attributes.count).to eq(3)

    expect(samples.first._attributes).to include(
      have_attributes(
        attribute_name:  'sample_name',
        attribute_value: 'MTB313',
        seq_no:          1
      )
    )

    expect(samples.first.links.count).to eq(0)

    xml = samples.first.xmls.sole

    expect(xml).to have_attributes(
      version: 1,
      content: instance_of(String)
    )

    expect(Nokogiri::XML.parse(xml.content).at('/BioSample/Description/SampleName').text).to eq('MTB313')

    expect(samples.second).to have_attributes(
      submission_id: 'SSUB000001',
      sample_name:   'MTB314',
      release_type:  'release',
      release_date:  nil,
      package_group: 'MIGS.ba',
      package:       'MIGS.ba.microbial',
      env_package:   'microbial mat/biofilm',
      status_id:     'submission_accepted'
    )

    expect(samples.second._attributes.count).to eq(3)

    expect(samples.second._attributes).to include(
      have_attributes(
        attribute_name:  'sample_name',
        attribute_value: 'MTB314',
        seq_no:          1
      )
    )

    expect(samples.second.links.count).to eq(0)

    xml = samples.second.xmls.sole

    expect(xml).to have_attributes(
      version: 1,
      content: instance_of(String)
    )

    expect(Nokogiri::XML.parse(xml.content).at('/BioSample/Description/SampleName').text).to eq('MTB314')
  end

  example 'submission id is overflow' do
    travel_to '2024-01-02 12:34:56'

    BioSample::SubmissionForm.create! submission_id: 'SSUB999999', submitter_id: user.uid, status_id: :new

    expect {
      Database::BioSample::Submitter.new.submit create_submission(file_fixture('biosample/SSUB000019_db_ok.xml'))
    }.to raise_error(Database::BioSample::Submitter::SubmissionIDOverflow)

    expect(BioSample::SubmissionForm.count).to eq(1)

    expect(BioSample::OperationHistory.sole).to have_attributes(
      type:          'fatal',
      summary:       '[repository:CreateNewSubmission] Number of submission surpass the upper limit',
      date:          '2024-01-02 12:34:56'.to_time,
      submitter_id:  'alice',
      submission_id: nil
    )
  end

  example 'two BioSample, inconsistent contact' do
    travel_to '2024-01-02 12:34:56'

    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_contact.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Owner/Contacts/Contact:})

    expect(BioSample::SubmissionForm.count).to eq(0)

    expect(BioSample::OperationHistory.sole).to have_attributes(
      type:          'error',
      summary:       '[repository:CreateNewSubmission] rollback transaction',
      date:          '2024-01-02 12:34:56'.to_time,
      submitter_id:  'alice',
      submission_id: nil
    )
  end

  example 'two BioSample, inconsistent model' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_model.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Models/Model:})
  end

  example 'two BioSample, inconsistent attributes' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_attributes.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Attributes/Attribute/@attribute_name:})
  end

  example 'two BioSample, inconsistent organization' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_organization.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Owner/Name:})
  end

  example 'two BioSample, inconsistent organization_url' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_organization_url.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Owner/Name/@url:})
  end

  example 'two BioSample, inconsistent comment' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_comment.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Description/Comment/Paragraph:})
  end

  example 'two BioSample, inconsistent link' do
    submission = create_submission(file_fixture('biosample/SSUB000019_db_ok_inconsistent_link.xml'))

    expect {
      Database::BioSample::Submitter.new.submit submission
    }.to raise_error(%r{Inconsistent Links/Link:})
  end
end
