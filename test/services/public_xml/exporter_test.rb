require 'test_helper'

class PublicXML::ExporterTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Dir.mktmpdir)
  end

  teardown do
    @output_dir.rmtree if @output_dir&.exist?
  end

  test 'writes one Package per public record, atomic rename, creates completed PublicXMLRun' do
    submissions(:bioproject).append_update!({'project' => {'accession' => 'PRJDB000123', 'title' => 'one'}}, actor: 'test')
    projects(:primary).update!(accession: 'PRJDB000123', status: 'public')

    run = nil
    assert_difference 'PublicXMLRun.count', 1 do
      run = PublicXML::Exporter.new(
        db:             'bioproject',
        kind:           'public',
        output_dir:     @output_dir,
        filename:       'test.xml',
        renderer_class: PublicXML::Bp::PackageRenderer,
        scope:          Project.status_public.where(submission: submissions(:bioproject)).includes(:submission)
      ).call
    end

    final   = @output_dir.join('test.xml')
    partial = @output_dir.join('test.xml.partial')

    assert final.exist?,         'final file must be present after atomic rename'
    assert_not partial.exist?,   '.partial must be cleaned up by the rename'

    xml = Nokogiri::XML(final.read)
    assert_equal 'PackageSet', xml.root.name
    assert_equal 1,            xml.root.xpath('./Package').size
    assert_equal 'PRJDB000123', xml.root.at_xpath('./Package/Project/Project/ProjectID/ArchiveID/@accession').value

    assert_equal 'completed', run.status
    assert_equal 1,           run.emitted
    assert_not_nil run.finished_at
  end

  test 'skips records whose submission has no materialised record' do
    # `projects(:umbrella)` is public but its submission has no updates,
    # so materialised_record is nil and the exporter must skip it.
    projects(:umbrella).update!(accession: 'PRJDB000999')

    run = PublicXML::Exporter.new(
      db:             'bioproject',
      kind:           'public',
      output_dir:     @output_dir,
      filename:       'test.xml',
      renderer_class: PublicXML::Bp::PackageRenderer,
      scope:          Project.status_public.includes(:submission)
    ).call

    assert_equal 0,           run.emitted
    assert_equal 'completed', run.status

    xml = Nokogiri::XML(@output_dir.join('test.xml').read)
    assert_equal 'PackageSet', xml.root.name
    assert_equal 0,            xml.root.xpath('./Package').size
  end

  test 'memoises materialised_record once per submission across sibling rows' do
    submission = submissions(:biosample)
    submission.append_update!({
      'samples' => [
        {'alias' => samples(:first).sample_name, 'package' => 'Generic.1.0'},
        {'alias' => samples(:second).sample_name, 'package' => 'Generic.1.0'}
      ]
    }, actor: 'test')

    samples(:first).update!(accession: 'SAMD00000901', status: 'public')
    samples(:second).update!(accession: 'SAMD00000902', status: 'public')

    call_count    = 0
    submission_id = submission.id
    Submission.class_eval do
      alias_method :__orig_materialised_record, :materialised_record
      define_method(:materialised_record) {
        call_count += 1 if id == submission_id
        __orig_materialised_record
      }
    end

    begin
      PublicXML::Exporter.new(
        db:             'biosample',
        kind:           'public',
        output_dir:     @output_dir,
        filename:       'bs.xml',
        renderer_class: PublicXML::Bs::BioSampleRenderer,
        scope:          Sample.status_public.includes(:submission).order(:id)
      ).call
    ensure
      Submission.class_eval do
        alias_method :materialised_record, :__orig_materialised_record
        remove_method :__orig_materialised_record
      end
    end

    assert_equal 1, call_count, 'materialised_record must be called once per submission, not once per sample'

    xml = Nokogiri::XML(@output_dir.join('bs.xml').read)
    assert_equal 2, xml.root.xpath('./BioSample').size
  end

  test 'marks run failed and re-raises when rendering blows up' do
    submissions(:bioproject).append_update!({'project' => {'title' => 'one'}}, actor: 'test')
    projects(:primary).update!(status: 'public')

    bomb = Class.new do
      def initialize(**); end
      def call = raise 'kaboom'
    end

    assert_raises RuntimeError, 'kaboom' do
      PublicXML::Exporter.new(
        db:             'bioproject',
        kind:           'public',
        output_dir:     @output_dir,
        filename:       'test.xml',
        renderer_class: bomb,
        scope:          Project.status_public.where(submission: submissions(:bioproject)).includes(:submission)
      ).call
    end

    run = PublicXMLRun.last
    assert_equal 'failed', run.status
    assert_match(/kaboom/, run.error_log)
    assert_not_nil run.finished_at

    # `.partial` is intentionally left behind for inspection; the final
    # name MUST NOT exist so consumers don't pick up a torn file.
    assert_not @output_dir.join('test.xml').exist?
    assert     @output_dir.join('test.xml.partial').exist?
  end
end
