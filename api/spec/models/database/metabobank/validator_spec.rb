require 'rails_helper'

RSpec.describe Database::MetaboBank::Validator, type: :model do
  example 'valid' do
    validation = create(:validation, id: 42, db: 'MetaboBank') { |validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
    }

    Database::MetaboBank::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      {
        object_id: '_base',
        validity:  nil,
        details:   [],
        file:      nil
      },
      {
        object_id: 'IDF',
        validity:  'valid',

        details: [
          code:     'MB_IR0037',
          severity: 'error_ignore',
          message:  instance_of(String)
        ],

        file: {
          path: 'MTBKS231.idf.txt',
          url:  'http://www.example.com/api/validations/42/files/MTBKS231.idf.txt'
        }
      },
      {
        object_id: 'SDRF',
        validity:  'valid',
        details:   instance_of(Array),

        file: {
          path: 'MTBKS231.sdrf.txt',
          url:  'http://www.example.com/api/validations/42/files/MTBKS231.sdrf.txt'
        }
      }
    )
  end

  example 'with MAF and RawDataFile and ProcessedDataFile, valid' do
    validation = create(:validation, id: 42, db: 'MetaboBank') { |validation|
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

    Database::MetaboBank::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: '_base',
        validity:  nil
      ),
      include(
        object_id: 'IDF',
        validity:  'valid'
      ),
      include(
        object_id: 'SDRF',
        validity:  'valid'
      ),
      include(
        object_id: 'MAF',
        validity:  'valid'
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/010_10_1_010.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/011_11_4_011.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/012_12_7_012.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/013_13_10_013.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/014_14_13_014.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/015_15_16_015.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/016_16_2_016.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/017_17_5_017.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/018_18_8_018.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/019_19_11_019.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/020_20_14_020.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/021_21_17_021.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/022_22_3_022.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/023_23_6_023.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/024_24_9_024.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/025_25_12_025.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/026_26_15_026.lcd')
      ),
      include(
        object_id: 'RawDataFile',
        validity:  'valid',
        file:      include(path: 'raw/027_27_18_027.lcd')
      ),
      include(
        object_id: 'ProcessedDataFile',
        validity:  'valid'
      )
    )

    expect(validation.results.size).to eq(23)
  end

  example 'with BioSample, valid' do
    validation = create(:validation, id: 42, db: 'MetaboBank') { |validation|
      create :obj, validation:, _id: 'IDF',       file: file_fixture_upload('metabobank/valid/MTBKS231.idf.txt')
      create :obj, validation:, _id: 'SDRF',      file: file_fixture_upload('metabobank/valid/MTBKS231.sdrf.txt')
      create :obj, validation:, _id: 'BioSample', file: file_fixture_upload('metabobank/valid/MTBKS231.bs.tsv')
    }

    Database::MetaboBank::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: '_base',
        validity:  nil
      ),
      include(
        object_id: 'IDF',
        validity:  'valid'
      ),
      include(
        object_id: 'SDRF',
        validity:  'valid'
      ),
      include(
        object_id: 'BioSample',
        validity:  'valid'
      )
    )
  end

  example 'invalid' do
    validation = create(:validation, id: 42, db: 'MetaboBank') { |validation|
      create :obj, validation:, _id: 'IDF',  file: file_fixture_upload('metabobank/invalid/MTBKS201.idf.txt')
      create :obj, validation:, _id: 'SDRF', file: file_fixture_upload('metabobank/invalid/MTBKS201.sdrf.txt')
    }

    Database::MetaboBank::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: '_base',
        validity:  nil
      ),
      include(
        object_id: 'IDF',
        validity:  'valid'
      ),
      include(
        object_id: 'SDRF',
        validity:  'invalid'
      )
    )
  end
end
