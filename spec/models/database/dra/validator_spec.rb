require 'rails_helper'

RSpec.describe Database::DRA::Validator, type: :model do
  example 'valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Database::DRA::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      {
        object_id: '_base',
        validity:  nil,
        details:   [],
        file:      nil
      },
      {
        object_id: 'Submission',
        validity:  'valid',
        details:   [],

        file: {
          path: 'example-0001_dra_Submission.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Submission.xml'
        }
      },
      {
        object_id: 'Experiment',
        validity:  'valid',
        details:   [],

        file: {
          path: 'example-0001_dra_Experiment.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Experiment.xml'
        }
      },
      {
        object_id: 'Run',
        validity:  'valid',
        details:   [],

        file: {
          path: 'example-0001_dra_Run.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Run.xml'
        }
      },
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   [],

        file: {
          path: 'runfile.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile.xml'
        }
      }
    )
  end

  example 'invalid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/example-0003_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/example-0003_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/example-0003_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Database::DRA::Validator.new.validate validation
    validation.reload

    expect(validation.results).to contain_exactly(
      include(
        object_id: '_base',
        validity:  nil
      ),
      include(
        object_id: 'Submission',
        validity:  'invalid',

        details: [
          code:     nil,
          severity: 'error',
          message:  '18:1: FATAL: Premature end of data in tag SUBMISSION line 2'
        ]
      ),
      include(
        object_id: 'Experiment',
        validity:  'invalid'
      ),
      include(
        object_id: 'Run',
        validity:  'invalid'
      ),
      include(
        object_id: 'RunFile',
        validity:  'valid'
      )
    )
  end

  example 'with Analysis and AnalysisFile, valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission',   file: file_fixture_upload('dra/example-0002_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment',   file: file_fixture_upload('dra/example-0002_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',          file: file_fixture_upload('dra/example-0002_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',      file: uploaded_file(name: 'runfile.xml')
      create :obj, validation:, _id: 'Analysis',     file: file_fixture_upload('dra/example-0002_dra_Analysis.xml')
      create :obj, validation:, _id: 'AnalysisFile', file: uploaded_file(name: 'analysisfile.xml')
    }

    Database::DRA::Validator.new.validate validation
    validation.reload

    expect(validation.results).to include(
      {
        object_id: 'Analysis',
        validity:  'valid',
        details:   [],

        file: {
          path: 'example-0002_dra_Analysis.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0002_dra_Analysis.xml'
        }
      },
      {
        object_id: 'AnalysisFile',
        validity:  'valid',
        details:   [],

        file: {
          path: 'analysisfile.xml',
          url:  'http://www.example.com/api/validations/42/files/analysisfile.xml'
        }
      }
    )
  end

  example 'with multiple RunFile, valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile1.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile2.xml')
    }

    Database::DRA::Validator.new.validate validation
    validation.reload

    expect(validation.results).to include(
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   [],

        file: {
          path: 'runfile1.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile1.xml'
        }
      },
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   [],

        file: {
          path: 'runfile2.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile2.xml'
        }
      }
    )
  end
end
