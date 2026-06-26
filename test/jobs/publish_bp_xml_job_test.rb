require 'test_helper'

class PublishBpXMLJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Rails.application.config_for(:app).public_xml_bp_dir!.tap { Pathname.new(it).mkpath }
  end

  teardown do
    Pathname.new(@output_dir).rmtree if Pathname.new(@output_dir).exist?
  end

  test 'runs end-to-end against the configured directory and records a PublicXMLRun' do
    submissions(:bioproject).append_update!({'project' => {'accession' => 'PRJDB000123', 'title' => 'BP job test'}}, actor: 'test')
    projects(:primary).update!(accession: 'PRJDB000123', status: 'public')

    assert_difference 'PublicXMLRun.where(db: "bioproject", kind: "public").count', 1 do
      PublishBpXMLJob.perform_now
    end

    file = Pathname.new(@output_dir).join(PublishBpXMLJob::FILENAME)
    assert file.exist?

    xml = Nokogiri::XML(file.read)
    assert_equal 'PackageSet', xml.root.name
    assert_includes xml.root.xpath('./Package/Project/Project/ProjectID/ArchiveID/@accession').map(&:value), 'PRJDB000123'
  end

  test 'skips when a previous run is still in flight (concurrency guard)' do
    PublicXMLRun.create!(db: 'bioproject', kind: 'public', status: 'running', started_at: 1.minute.ago)

    assert_no_difference 'PublicXMLRun.count' do
      PublishBpXMLJob.perform_now
    end
  end
end
