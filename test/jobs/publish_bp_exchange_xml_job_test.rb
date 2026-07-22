require 'test_helper'

class PublishBpExchangeXMLJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Rails.application.config_for(:app).public_xml_dir!.tap { Pathname.new(it).mkpath }
  end

  teardown do
    # Shared output dir — remove only this job's file(s).
    Pathname.new(@output_dir).glob("#{PublishBpExchangeXMLJob::FILENAME}*").each(&:delete)
  end

  test 'emits a PackageSet whose Packages carry a Processing element and records an exchange run' do
    submissions(:bioproject).append_update!({'project' => {'accession' => 'PRJDB000123', 'title' => 'Exchange job test'}}, actor: 'test')
    projects(:primary).update!(accession: 'PRJDB000123', status: 'public', release_date: Date.current)

    # A completed public run in the past puts today's release inside the
    # delta window → the record should come out as eAdded.
    PublicXMLRun.create!(db: 'bioproject', kind: 'public', status: 'completed', started_at: 1.week.ago, finished_at: 1.week.ago)

    assert_difference 'PublicXMLRun.where(db: "bioproject", kind: "exchange").count', 1 do
      PublishBpExchangeXMLJob.perform_now
    end

    file = Pathname.new(@output_dir).join(PublishBpExchangeXMLJob::FILENAME)
    assert file.exist?

    xml = Nokogiri::XML(file.read)
    assert_equal 'PackageSet', xml.root.name

    processing = xml.root.at_xpath('./Package/Processing')
    assert_not_nil processing, 'each Package must carry a Processing element'
    assert_equal 'DDBJ',   processing['owner']
    assert_equal '000123', processing['id']
    assert_equal 'eAdded', processing['action']
  end

  test 'skips when a previous exchange run is still in flight (concurrency guard)' do
    PublicXMLRun.create!(db: 'bioproject', kind: 'exchange', status: 'running', started_at: 1.minute.ago)

    assert_no_difference 'PublicXMLRun.count' do
      PublishBpExchangeXMLJob.perform_now
    end
  end
end
