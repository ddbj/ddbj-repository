require 'test_helper'

class PublishDRAXMLJobTest < ActiveSupport::TestCase
  setup do
    @private = Pathname.new(Rails.application.config_for(:app).output_dir!).join('private')
  end

  teardown do
    @private.join('dra').rmtree if @private.join('dra').exist?
    DRA::PublicationRequests.default.root.rmtree if DRA::PublicationRequests.default.root.exist?
  end

  # The public tree is the mover's to write (script/dra-mover).
  test 'asks for the public tree from the private one under the configured directory, and records a PublicXMLRun' do
    DwayTakeover.record!(by: 'test')

    row = dra_submissions(:dra)
    row.submission.append_update! JSON.parse(file_fixture('dra/record/DRA000001.json').read), actor: 'test'
    row.update! status: :public, first_published_at: Time.current, last_published_at: Time.current

    assert_difference 'PublicXMLRun.where(db: "dra", kind: "public").count', 1 do
      PublishDRAXMLJob.perform_now
    end

    assert @private.join('dra', 'fastq', 'DRA000', 'DRA000001', 'DRA000001.experiment.xml').exist?
    assert_equal ['DRA000001'], DRA::PublicationRequests.default.outstanding.to_a
  end

  # The tree is D-way's, which its release writes until then.
  test 'asks for nothing before D-way has handed over' do
    assert_no_difference 'PublicXMLRun.count' do
      PublishDRAXMLJob.perform_now
    end

    assert_empty DRA::PublicationRequests.default.outstanding
    assert_not @private.join('dra', 'fastq').exist?
  end
end
