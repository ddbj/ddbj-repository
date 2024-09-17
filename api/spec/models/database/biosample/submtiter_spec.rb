require 'rails_helper'

RSpec.describe Database::BioSample::Submitter do
  let(:user) { create(:user, uid: 'alice') }

  example 'submit' do
    submission = create(:submission, **{
      validation: build(:validation, :valid, **{
        user:,

        objs: [
          build(:obj, **{
            _id:      'BioSample',
            file:     file_fixture('biosample/SSUB000019_db_fail.xml'),
            validity: :valid
          })
        ]
      })
    })

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

    Database::BioSample::Submitter.new.submit submission

    expect(BioSample::ContactForm.sole).to have_attributes(
      submission_id: 'SSUB000001',
      first_name:    'Haruno',
      last_name:     'Yoshida',
      email:         'harunoy@lisci.kitasato-u.ac.jp.ddbj.test',
      seq_no:        1
    )

    attribute_file = {
      sample_name:        'MTB313',
      strains:            'MTB313',
      env_biome:          'urban biome',
      collection_date:    '2011-12-1T1:2:3',
      env_feature:        'town',
      geo_loc_name:       'Japan: Hikone-shi',
      lat_lon:            '136.225389 35.262246',
      env_material:       'interstitial fluid',
      project_name:       'Streptococcus pyogenes MTB313 genome sequencing',
      isol_growth_condt:  '24464696',
      num_replicons:      '1',
      ref_biomaterial:    '16088826',
      elev:               '88.8m',
      depth:              '0m',
      bioproject_id:      'PRJDB1654',
      culture_collection: 'Coriell: 1234',
      specimen_voucher:   'ATCC:1234'
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
      package:             "MIGS.ba.microbial",
      env_package:         "microbial mat/biofilm"
    )

    expect(BioSample::LinkForm.count).to eq(0)

    ext_entity = DRMDB::ExtEntity.sole

    expect(ext_entity).to have_attributes(
      acc_type: 'study',
      ref_name: 'SSUB000001',
      status:   'inputting'
    )

    expect(DRMDB::ExtPermit.sole).to have_attributes(
      ext_id:       ext_entity.ext_id,
      submitter_id: 'alice'
    )
  end
end
