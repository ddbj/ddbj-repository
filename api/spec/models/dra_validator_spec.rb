require 'rails_helper'

RSpec.describe DraValidator, type: :model do
  example 'valid' do
    request = create(:request, db: 'DRA') {|request|
      create :obj, request:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, request:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, request:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, request:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Validators.validate request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(request.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'Submission',
        path:      'example-0001_dra_Submission.xml',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'Experiment',
        path:      'example-0001_dra_Experiment.xml',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'Run',
        path:      'example-0001_dra_Run.xml',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'RunFile',
        path:      'runfile.xml',
        validity:  'valid',
        details:   nil
      }
    )
  end

  example 'invalid' do
    request = create(:request, db: 'DRA') {|request|
      create :obj, request:, _id: 'Submission', file: file_fixture_upload('dra/invalid/example-0001_dra_Submission.xml')
      create :obj, request:, _id: 'Experiment', file: file_fixture_upload('dra/invalid/example-0001_dra_Experiment.xml')
      create :obj, request:, _id: 'Run',        file: file_fixture_upload('dra/invalid/example-0001_dra_Run.xml')
      create :obj, request:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    Validators.validate request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'invalid'
    )

    expect(request.validation_reports).to contain_exactly(
      {
        object_id: '_base',
        path:      nil,
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'Submission',
        path:      'example-0001_dra_Submission.xml',
        validity:  'invalid',

        details: [
          'object_id' => 'Submission',
          'message'   => '18:1: FATAL: Premature end of data in tag SUBMISSION line 2'
        ]
      },
      {
        object_id: 'Experiment',
        path:      'example-0001_dra_Experiment.xml',
        validity:  'invalid',
        details:   instance_of(Array)
      },
      {
        object_id: 'Run',
        path:      'example-0001_dra_Run.xml',
        validity:  'invalid',
        details:   instance_of(Array)
      },
      {
        object_id: 'RunFile',
        path:      'runfile.xml',
        validity:  'valid',
        details:   nil
      }
    )
  end

  example 'error' do
    request = create(:request, db: 'DRA') {|request|
      create :obj, request:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, request:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, request:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, request:, _id: 'RunFile',    file: uploaded_file(name: 'runfile.xml')
    }

    allow(Open3).to receive(:capture2e) { ['Something went wrong.', double(success?: false)] }

    Validators.validate request

    expect(request).to have_attributes(
      status: 'finished',
      validity: 'error'
    )

    expect(request.validation_reports).to include(
      object_id: '_base',
      path:      nil,
      validity:  'error',

      details: {
        'error' => 'Something went wrong.'
      }
    )

    expect(request.submission).to be_nil
  end

  example 'with Analysis and AnalysisFile, valid' do
    request = create(:request, db: 'DRA') {|request|
      create :obj, request:, _id: 'Submission',   file: file_fixture_upload('dra/valid/example-0002_dra_Submission.xml')
      create :obj, request:, _id: 'Experiment',   file: file_fixture_upload('dra/valid/example-0002_dra_Experiment.xml')
      create :obj, request:, _id: 'Run',          file: file_fixture_upload('dra/valid/example-0002_dra_Run.xml')
      create :obj, request:, _id: 'RunFile',      file: uploaded_file(name: 'runfile.xml')
      create :obj, request:, _id: 'Analysis',     file: file_fixture_upload('dra/valid/example-0002_dra_Analysis.xml')
      create :obj, request:, _id: 'AnalysisFile', file: uploaded_file(name: 'analysisfile.xml')
    }

    Validators.validate request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(request.validation_reports).to include(
      {
        object_id: 'Analysis',
        path:      'example-0002_dra_Analysis.xml',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'AnalysisFile',
        path:      'analysisfile.xml',
        validity:  'valid',
        details:   nil
      }
    )
  end

  example 'with multiple RunFile, valid' do
    request = create(:request, db: 'DRA') {|request|
      create :obj, request:, _id: 'Submission', file: file_fixture_upload('dra/valid/example-0001_dra_Submission.xml')
      create :obj, request:, _id: 'Experiment', file: file_fixture_upload('dra/valid/example-0001_dra_Experiment.xml')
      create :obj, request:, _id: 'Run',        file: file_fixture_upload('dra/valid/example-0001_dra_Run.xml')
      create :obj, request:, _id: 'RunFile',    file: uploaded_file(name: 'runfile1.xml')
      create :obj, request:, _id: 'RunFile',    file: uploaded_file(name: 'runfile2.xml')
    }

    Validators.validate request

    expect(request).to have_attributes(
      status:   'finished',
      validity: 'valid'
    )

    expect(request.validation_reports).to include(
      {
        object_id: 'RunFile',
        path:      'runfile1.xml',
        validity:  'valid',
        details:   nil
      },
      {
        object_id: 'RunFile',
        path:      'runfile2.xml',
        validity:  'valid',
        details:   nil
      }
    )
  end
end
