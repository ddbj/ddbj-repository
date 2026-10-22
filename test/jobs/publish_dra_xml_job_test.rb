require 'test_helper'

class PublishDRAXMLJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('public', 'dra')
  end

  teardown do
    @output_dir.rmtree if @output_dir.exist?
  end

  test 'writes the public tree under the configured directory and records a PublicXMLRun' do
    DwayTakeover.record!(by: 'test')

    row = dra_submissions(:dra)
    row.submission.append_update! JSON.parse(file_fixture('dra/record/DRA000001.json').read), actor: 'test'
    row.update! status: :public, first_published_at: Time.current, last_published_at: Time.current

    assert_difference 'PublicXMLRun.where(db: "dra", kind: "public").count', 1 do
      PublishDRAXMLJob.perform_now
    end

    assert @output_dir.join('fastq', 'DRA000', 'DRA000001', 'DRA000001.experiment.xml').exist?
  end

  # The tree is D-way's, which its release writes until then.
  test 'writes nothing before D-way has handed over' do
    assert_no_difference 'PublicXMLRun.count' do
      PublishDRAXMLJob.perform_now
    end

    assert_not @output_dir.exist?
  end
end
