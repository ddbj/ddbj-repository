require 'rails_helper'

RSpec.describe MetabobankValidator, type: :model do
  example 'valid' do
    validation = create(:validation, db: 'MetaboBank') {|validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'IDF',
        path:      'MTBKS231.idf.txt',
        validity:  'valid',

        details: [
          'object_id' => 'IDF',
          'code'      => 'MB_IR0037',
          'severity'  => 'error_ignore',
          'message'   => instance_of(String)
        ]
      },
      {
        object_id: 'SDRF',
        path:      'MTBKS231.sdrf.txt',
        validity:  'valid',
        details:   instance_of(Array)
      }
    )
  end

  example 'with MAF and RawDataFile and ProcessedDataFile, valid' do
    validation = create(:validation, db: 'MetaboBank') {|validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
      create :obj, validation:, _id: 'MAF',  file: file_fixture_upload('metabobank/valid/MTBKS231.maf.txt')

      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '010_10_1_010.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '011_11_4_011.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '012_12_7_012.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '013_13_10_013.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '014_14_13_014.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '015_15_16_015.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '016_16_2_016.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '017_17_5_017.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '018_18_8_018.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '019_19_11_019.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '020_20_14_020.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '021_21_17_021.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '022_22_3_022.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '023_23_6_023.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '024_24_9_024.lcd'),  destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '025_25_12_025.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '026_26_15_026.lcd'), destination: 'raw'
      create :obj, validation:, _id: 'RawDataFile', file: uploaded_file(name: '027_27_18_027.lcd'), destination: 'raw'

      create :obj, validation:, _id: 'ProcessedDataFile', file: uploaded_file(name: '220629_ppg_conc.txt'), destination: 'processed'
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to include(
      {
        object_id: 'MAF',
        path:      'MTBKS231.maf.txt',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'RawDataFile',
        path:      'raw/010_10_1_010.lcd',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'RawDataFile',
        path:      'raw/027_27_18_027.lcd',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'ProcessedDataFile',
        path:      'processed/220629_ppg_conc.txt',
        validity:  'valid',
        details:   nil
      }
    )

    expect(validation.validation_reports.size).to eq(23)
  end

  example 'with BioSample, valid' do
    validation = create(:validation, db: 'MetaboBank') {|validation|
      create :obj, validation:, _id: 'IDF',       file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF',      file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
      create :obj, validation:, _id: 'BioSample', file: file_fixture_upload('metabobank/valid/MTBKS231.bs.tsv')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to include(
      object_id: 'BioSample',
      path:      'MTBKS231.bs.tsv',
      validity:  'valid',
      details:   nil
    )
  end

  example 'invalid' do
    validation = create(:validation, db: 'MetaboBank') {|validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/invalid/MTBKS201.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/invalid/MTBKS201.sdrf.txt')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      status:   'finished',
      validity: 'invalid'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'IDF',
        path:      'MTBKS201.idf.txt',
        validity:  'valid',
        details:   instance_of(Array)
      },
      {
        object_id: 'SDRF',
        path:      'MTBKS201.sdrf.txt',
        validity:  'invalid',
        details:   instance_of(Array)
      }
    )
  end
end
