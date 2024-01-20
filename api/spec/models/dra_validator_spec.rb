require 'rails_helper'

RSpec.describe DraValidator, type: :model do
  example 'valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        validity:  'valid',
        details:   nil,
        file:      nil
      },
      {
        object_id: 'Submission',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'example-0001_dra_Submission.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Submission.xml'
        }
      },
      {
        object_id: 'Experiment',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'example-0001_dra_Experiment.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Experiment.xml'
        }
      },
      {
        object_id: 'Run',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'example-0001_dra_Run.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Run.xml'
        }
      },
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'runfile.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile.xml'
        }
      }
    )
  end

  example 'invalid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/invalid/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/invalid/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/invalid/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'invalid'
    )

    expect(validation.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        validity:  'valid',
        details:   nil,
        file:      nil
      },
      {
        object_id: 'Submission',
        validity:  'invalid',

        details: [
          'object_id' => 'Submission',
          'message'   => '18:1: FATAL: Premature end of data in tag SUBMISSION line 2'
        ],

        file: {
          path: 'example-0001_dra_Submission.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Submission.xml'
        }
      },
      {
        object_id: 'Experiment',
        validity:  'invalid',
        details:   instance_of(Array),

        file: {
          path: 'example-0001_dra_Experiment.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Experiment.xml'
        }
      },
      {
        object_id: 'Run',
        validity:  'invalid',
        details:   instance_of(Array),

        file: {
          path: 'example-0001_dra_Run.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0001_dra_Run.xml'
        }
      },
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'runfile.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile.xml'
        }
      }
    )
  end

  example 'error' do
    validation = create(:validation, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    allow(Open3).to receive(:capture2e) { ['Something went wrong.', double(success?: false)] }

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'error'
    )

    expect(validation.validation_reports).to include(
      object_id: '_base',
      validity:  'error',

      details: {
        'error' => 'Something went wrong.'
      },

      file: nil
    )

    expect(validation.submission).to be_nil
  end

  example 'with Analysis and AnalysisFile, valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission',   file: file_fixture_upload('dra/valid/example-0002_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment',   file: file_fixture_upload('dra/valid/example-0002_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',          file: file_fixture_upload('dra/valid/example-0002_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',      file: uploaded_file(name: 'runfile.xml')
      create :obj, validation:, _id: 'Analysis',     file: file_fixture_upload('dra/valid/example-0002_dra_Analysis.xml')
      create :obj, validation:, _id: 'AnalysisFile', file: uploaded_file(name: 'analysisfile.xml')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to include(
      {
        object_id: 'Analysis',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'example-0002_dra_Analysis.xml',
          url:  'http://www.example.com/api/validations/42/files/example-0002_dra_Analysis.xml'
        }
      },
      {
        object_id: 'AnalysisFile',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'analysisfile.xml',
          url:  'http://www.example.com/api/validations/42/files/analysisfile.xml'
        }
      }
    )
  end

  example 'with multiple RunFile, valid' do
    validation = create(:validation, id: 42, db: 'DRA') {|validation|
      create :obj, validation:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, validation:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, validation:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile1.xml')
      create :obj, validation:, _id: 'RunFile',    file: uploaded_file(name: 'runfile2.xml')
    }

    Validators.validate validation

    expect(validation).to have_attributes(
      progress: 'finished',
      validity: 'valid'
    )

    expect(validation.validation_reports).to include(
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'runfile1.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile1.xml'
        }
      },
      {
        object_id: 'RunFile',
        validity:  'valid',
        details:   nil,

        file: {
          path: 'runfile2.xml',
          url:  'http://www.example.com/api/validations/42/files/runfile2.xml'
        }
      }
    )
  end
end
