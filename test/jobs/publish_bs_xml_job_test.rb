require 'test_helper'

class PublishBsXMLJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('public').tap(&:mkpath)
  end

  teardown do
    # The output dir is shared across DBs now, so remove only this job's
    # file(s) (the final + any leftover .partial) rather than the dir.
    Pathname.new(@output_dir).glob("#{PublishBsXMLJob::FILENAME}*").each(&:delete)
  end

  test 'runs end-to-end against the configured directory and records a PublicXMLRun' do
    submissions(:biosample).append_update!({
      'submission' => {
        'submitters' => [{'first_name' => 'A', 'organizations' => [{'name' => 'DDBJ'}]}]
      },
      'samples'    => [{
        'alias'   => samples(:second).sample_name,
        'title'   => 'BS job test sample',
        'package' => 'Generic.1.0'
      }]
    }, actor: 'test')

    samples(:second).update!(accession: 'SAMD00000222', status: 'public', release_date: Date.new(2026, 6, 1))

    assert_difference 'PublicXMLRun.where(db: "biosample", kind: "public").count', 1 do
      PublishBsXMLJob.perform_now
    end

    file = Pathname.new(@output_dir).join(PublishBsXMLJob::FILENAME)
    assert file.exist?

    xml = Nokogiri::XML(file.read)
    assert_equal 'BioSampleSet', xml.root.name

    # 公開 XML では accession は BioSample の属性ではなく Id として出る。
    bs = xml.root.at_xpath('./BioSample[Ids/Id[@namespace="BioSample"]="SAMD00000222"]')
    assert_not_nil bs
    assert_equal 'DDBJ', bs.at_xpath('./Owner/Name').text
    assert_nil   bs.at_xpath('./Owner/Contacts'), 'BS public XML must strip Contacts'
  end
end
