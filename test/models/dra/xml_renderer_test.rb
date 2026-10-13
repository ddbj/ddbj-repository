require 'test_helper'

class DRA::XMLRendererTest < ActiveSupport::TestCase
  FIXTURES = Rails.root.join('test/fixtures/files/dra')

  def converted(name) = DRA::Converter.new(documents: FIXTURES.join(name).glob('*.xml').sort.map(&:read)).call

  def record = JSON.parse(FIXTURES.join('record/DRA000001.json').read)

  # What a document says, as lines a path each with its attributes and
  # text — in the version's terms: an attribute it has no place for, and
  # an element saying nothing (`<TITLE></TITLE>`, which the converter
  # reads as none), are not counted.
  def said(document, kind)
    allowed = version(kind)
    lines   = []
    walk    = ->(node, path) {
      attributes = node.attribute_nodes.select { it.value.present? && allowed.include?("#{path}/@#{it.name}") }.sort_by(&:name).map { "@#{it.name}=#{it.value}" }
      text       = node.children.select(&:text?).map(&:content).join.strip
      before     = lines.size

      node.element_children.each { walk.(it, "#{path}/#{it.name}") }

      lines.insert(before, [path, *attributes, text].join(' ').strip) if attributes.any? || text.present? || lines.size > before
    }

    roots = document.root.name.end_with?('_SET') ? document.root.element_children : [document.root]
    roots.each { walk.(it, it.name) }

    lines
  end

  def version(kind)
    paths = Set.new
    walk  = ->(element, path) {
      element.attributes.each_key { paths << "#{path}/@#{it}" }
      element.children.each { walk.(it, "#{path}/#{it.name}") }
    }

    walk.(DRA::XSD.root(kind), kind.upcase)
    paths
  end

  # The table and the version agree: what the version has, the table says
  # where in a record it goes.
  test 'every element and attribute of the version has a place in the table' do
    DRA::XMLRenderer::KINDS.each do |kind|
      walk = ->(element, path) {
        assert DRA::Mapping.place(kind, path), "#{path} is not in the table"

        element.attributes.each_key { assert DRA::Mapping.place(kind, "#{path}/@#{it}"), "#{path}/@#{it} is not in the table" }
        element.children.each { walk.(it, "#{path}/#{it.name}") }
      }

      walk.(DRA::XSD.root(kind), kind.upcase)
    end
  end

  # D-way's own documents, read into records and written back.
  %w[DRA000072 DRA000368 ERA000075 SRA000267].each do |name|
    test "#{name} comes back valid, saying what it said" do
      documents = DRA::XMLRenderer.new(converted(name)).call

      FIXTURES.join(name).glob('*.xml').each do |file|
        kind     = file.basename.to_s.split('.')[1]
        document = documents.fetch(kind)

        assert_empty DRA::XSD.schema(kind).validate(document).map(&:message), "#{name} #{kind}"
        assert_equal said(Nokogiri::XML(file.read), kind).sort, said(document, kind).sort, "#{name} #{kind}"
      end
    end
  end

  # Every DRA submission the spec keeps, from D-way's archive: valid as
  # written back wherever it was valid as sent (SRA000234 states its BED
  # files as `BED`, which no version takes) — but for DRA000161, whose
  # assembly was a CUSTOM one of empty links. The record keeps nothing of
  # it, and which kind of assembly it was is not the renderer's to guess.
  SPEC = Rails.root.join('vendor/ddbj-record-specifications/tests/fixtures/v3/raw/dra')

  UNSAID = {'DRA000161' => 'analysis'}.freeze

  test 'every submission of the spec\'s comes back valid where it was' do
    SPEC.children.sort.each do |directory|
      files     = directory.glob('*.xml')
      documents = DRA::XMLRenderer.new(DRA::Converter.new(documents: files.map(&:read)).call).call

      files.each do |file|
        kind = file.basename.to_s.split('.')[1]

        next if DRA::XSD.schema(kind).validate(Nokogiri::XML(file.read)).any?

        errors = DRA::XSD.schema(kind).validate(documents.fetch(kind)).map(&:message)

        if UNSAID[directory.basename.to_s] == kind
          assert_not_empty errors, "#{directory.basename} #{kind} is refused, not made to say it"
        else
          assert_empty errors, "#{directory.basename} #{kind}"
        end
      end
    end
  end

  # A run's document names each run's experiment: resolved one by one, a
  # thousand runs took minutes.
  test 'a thousand runs are written in moments' do
    many = record.tap {|many|
      many['runs']      = (1..1_000).map { {'alias' => "run#{it}", 'accession' => format('DRR%06d', it)} }
      many['relations'] = many['relations'].first(2) + (1..1_000).map { {'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => "run#{it}"}, 'target' => {'db' => 'experiment', 'id' => 'tumor-exp'}} }
    }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    runs    = DRA::XMLRenderer.new(many).call.fetch('run')

    assert_equal 1_000, runs.xpath('//EXPERIMENT_REF').size
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end

  # The converter drops an empty text element; the version requires some
  # (`<STEP_INDEX></STEP_INDEX>` in a PIPE_SECTION), so they come back
  # empty — beside what their parent does hold, and not on their own.
  test 'a required element with nothing to say is written empty, alongside what its parent holds' do
    experiment = DRA::XMLRenderer.new(converted('DRA000368')).call.fetch('experiment')
    section    = experiment.at_xpath('//PIPE_SECTION')

    assert_equal %w[STEP_INDEX PREV_STEP_INDEX PROGRAM VERSION], section.element_children.map(&:name)
    assert_equal '', section.at_xpath('STEP_INDEX').content
  end

  # A choice the record says nothing of is not chosen for it: an
  # experiment with no library layout is not a single-end one.
  test 'a required choice the record has nothing for is left unwritten' do
    no_layout = record.tap { it['experiments'][0]['library'].except!('layout', 'nominal_length') }
    document  = DRA::XMLRenderer.new(no_layout).call.fetch('experiment')

    assert_empty document.xpath('//LIBRARY_LAYOUT/*')
    assert_not_empty DRA::XSD.schema('experiment').validate(document)
  end

  test 'a relation is written by the document of its source, and only once' do
    documents = DRA::XMLRenderer.new(record).call

    assert_equal ['PRJDB000001'], documents.fetch('experiment').xpath('//STUDY_REF/@accession').map(&:value)
    assert_equal ['SAMD00000001'], documents.fetch('experiment').xpath('//SAMPLE_DESCRIPTOR/@accession').map(&:value)
    assert_equal ['tumor-exp'], documents.fetch('run').xpath('//EXPERIMENT_REF/@refname').map(&:value)
  end

  # A SAMPLE_DESCRIPTOR names its sample or describes a pool, not both.
  test 'of the branches of a choice, the first holding something is written' do
    with_pool = record.tap {
      it['experiments'][0]['pool'] = {'members' => [{'member_name' => 'a', 'sample' => {'accession' => 'SAMD00000002'}}]}
      it['relations'][1]['target']['identifiers'] = [{'type' => 'primary', 'value' => 'SAMD00000001'}]
    }

    descriptor = DRA::XMLRenderer.new(with_pool).call.fetch('experiment').at_xpath('//SAMPLE_DESCRIPTOR')

    assert_equal %w[IDENTIFIERS], descriptor.element_children.map(&:name)
  end

  # D-way writes its dates as the start of the day in Tokyo.
  test 'a date is written as a moment where the version wants one' do
    run = DRA::XMLRenderer.new(record).call.fetch('run').at_xpath('//RUN')

    assert_equal '2026-04-01T00:00:00+09:00', run['run_date']
  end

  # sra_link_type has no element in this version: the link is written as
  # the xref it is.
  test 'a link is written by the element of its kind' do
    linked = record.tap {
      it['relations'] << {'type' => 'xref', 'source' => {'type' => 'experiment', 'alias' => 'tumor-exp'}, 'target' => {'db' => 'pubmed', 'id' => '123'}, 'properties' => {'sra_link_type' => 'ddbj'}}
      it['relations'] << {'type' => 'reference', 'source' => {'type' => 'experiment', 'alias' => 'tumor-exp'}, 'target' => {'url' => 'https://example.com'}, 'label' => 'Example'}
    }

    links = DRA::XMLRenderer.new(linked).call.fetch('experiment').xpath('//EXPERIMENT_LINK/*')

    assert_equal [%w[XREF_LINK pubmed], %w[URL_LINK https://example.com]], links.map { [it.name, it.at_xpath('DB | URL').content] }
  end

  test 'only the kinds the record has objects of' do
    assert_equal %w[submission experiment run], DRA::XMLRenderer.new(record).call.keys

    assert_equal %w[experiment run], DRA::XMLRenderer.new(record.except('submission')).call.keys
  end
end
