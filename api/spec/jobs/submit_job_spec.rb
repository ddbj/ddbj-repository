require 'rails_helper'

RSpec.describe SubmitJob, type: :job do
  let!(:user)          { create_default(:user, uid: 'alice') }
  let(:submission_dir) { Pathname.new(ENV.fetch('REPOSITORY_DIR')).join('alice/submissions/X-42') }

  example 'simple' do
    submission = create(:submission, id: 42, **{
      validation: create(:validation, :valid, db: 'MetaboBank') { |validation|
        create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt'), validity: 'valid'
        create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt'), validity: 'valid'
      }
    }).reload

    SubmitJob.perform_now submission

    expect(Dir.glob('**/*', base: submission_dir)).to match_array(%w[
      _base
      _base/validation-report.json
      IDF
      IDF/MTBKS231.idf.txt
      IDF/MTBKS231.idf.txt-validation-report.json
      SDRF
      SDRF/MTBKS231.sdrf.txt
      SDRF/MTBKS231.sdrf.txt-validation-report.json
      validation-report.json
    ])
  end

  example 'complex' do
    submission = create(:submission, id: 42, **{
      validation: create(:validation, :valid, db: 'MetaboBank') { |validation|
        create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt'),  validity: 'valid'
        create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt'), validity: 'valid'
        create :obj, validation:, _id: 'MAF',  file: file_fixture_upload('metabobank/valid/MTBKS231.maf.txt'),  validity: 'valid'

        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '010_10_1_010.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '011_11_4_011.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '012_12_7_012.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '013_13_10_013.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '014_14_13_014.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '015_15_16_015.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '016_16_2_016.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '017_17_5_017.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '018_18_8_018.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '019_19_11_019.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '020_20_14_020.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '021_21_17_021.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '022_22_3_022.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '023_23_6_023.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '024_24_9_024.lcd'),  destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '025_25_12_025.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '026_26_15_026.lcd'), destination: 'raw', validity: 'valid'
        create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '027_27_18_027.lcd'), destination: 'raw', validity: 'valid'

        create :obj, validation:, _id: 'ProcessedDataFile', file: uploaded_file(name: '220629_ppg_conc.txt'), destination: 'processed', validity: 'valid'
      }
    }).reload

    SubmitJob.perform_now submission

    expect(Dir.glob('**/*', base: submission_dir)).to match_array(%w[
      _base
      _base/validation-report.json
      IDF
      IDF/MTBKS231.idf.txt
      IDF/MTBKS231.idf.txt-validation-report.json
      SDRF
      SDRF/MTBKS231.sdrf.txt
      SDRF/MTBKS231.sdrf.txt-validation-report.json
      MAF
      MAF/MTBKS231.maf.txt
      MAF/MTBKS231.maf.txt-validation-report.json
      RawDataFile
      RawDataFile/raw
      RawDataFile/raw/010_10_1_010.lcd
      RawDataFile/raw/010_10_1_010.lcd-validation-report.json
      RawDataFile/raw/011_11_4_011.lcd
      RawDataFile/raw/011_11_4_011.lcd-validation-report.json
      RawDataFile/raw/012_12_7_012.lcd
      RawDataFile/raw/012_12_7_012.lcd-validation-report.json
      RawDataFile/raw/013_13_10_013.lcd
      RawDataFile/raw/013_13_10_013.lcd-validation-report.json
      RawDataFile/raw/014_14_13_014.lcd
      RawDataFile/raw/014_14_13_014.lcd-validation-report.json
      RawDataFile/raw/015_15_16_015.lcd
      RawDataFile/raw/015_15_16_015.lcd-validation-report.json
      RawDataFile/raw/016_16_2_016.lcd
      RawDataFile/raw/016_16_2_016.lcd-validation-report.json
      RawDataFile/raw/017_17_5_017.lcd
      RawDataFile/raw/017_17_5_017.lcd-validation-report.json
      RawDataFile/raw/018_18_8_018.lcd
      RawDataFile/raw/018_18_8_018.lcd-validation-report.json
      RawDataFile/raw/019_19_11_019.lcd
      RawDataFile/raw/019_19_11_019.lcd-validation-report.json
      RawDataFile/raw/020_20_14_020.lcd
      RawDataFile/raw/020_20_14_020.lcd-validation-report.json
      RawDataFile/raw/021_21_17_021.lcd
      RawDataFile/raw/021_21_17_021.lcd-validation-report.json
      RawDataFile/raw/022_22_3_022.lcd
      RawDataFile/raw/022_22_3_022.lcd-validation-report.json
      RawDataFile/raw/023_23_6_023.lcd
      RawDataFile/raw/023_23_6_023.lcd-validation-report.json
      RawDataFile/raw/024_24_9_024.lcd
      RawDataFile/raw/024_24_9_024.lcd-validation-report.json
      RawDataFile/raw/025_25_12_025.lcd
      RawDataFile/raw/025_25_12_025.lcd-validation-report.json
      RawDataFile/raw/026_26_15_026.lcd
      RawDataFile/raw/026_26_15_026.lcd-validation-report.json
      RawDataFile/raw/027_27_18_027.lcd
      RawDataFile/raw/027_27_18_027.lcd-validation-report.json
      ProcessedDataFile
      ProcessedDataFile/processed
      ProcessedDataFile/processed/220629_ppg_conc.txt
      ProcessedDataFile/processed/220629_ppg_conc.txt-validation-report.json
      validation-report.json
    ])
  end
end
