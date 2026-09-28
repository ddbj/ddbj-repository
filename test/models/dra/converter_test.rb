require 'test_helper'

class DRA::ConverterTest < ActiveSupport::TestCase
  FIXTURES      = Rails.root.join('test/fixtures/files/dra')
  SPEC_FIXTURES = Rails.root.join('vendor/ddbj-record-specifications/tests/fixtures/v3/raw/dra')
  KINDS         = %w[submission study sample experiment run analysis].freeze

  def documents(dir) = dir.glob('*.xml').sort_by { KINDS.index(it.basename.to_s.split('.')[1]) || raise("#{it}: no kind in its name") }.map(&:read)

  def convert(*xml) = DRA::Converter.new(documents: xml).call

  def parses(record) = DDBJRecord::V3::Parser.parse(Oj.dump(record, mode: :compat))

  def canonical(record) = JSON.parse(DDBJRecord::Canonicalizer.canonicalize(record))

  def link(url) = "<SAMPLE_LINKS><SAMPLE_LINK><URL_LINK><URL>#{url}</URL></URL_LINK></SAMPLE_LINK></SAMPLE_LINKS>"

  def refuses(xml, message)
    error = assert_raises(DRA::Converter::Unmapped) { convert(xml) }

    assert_match message, error.message
  end

  test 'the SRA documents of a submission become a record v3 reads and canonicalises' do
    FIXTURES.children.sort.each do |dir|
      record = convert(*documents(dir))

      assert_kind_of DDBJRecord::V3::Root, parses(record), dir.basename.to_s
      assert canonical(record), dir.basename.to_s
    end
  end

  test 'every raw SRA document of the spec converts' do
    # As in DDBJRecord::V3Test: the Canon workflow checks the submodule out.
    unless SPEC_FIXTURES.exist?
      flunk 'the submodule is not checked out' if ENV['REQUIRE_SPEC_SUBMODULE']

      skip 'the submodule is not checked out'
    end

    SPEC_FIXTURES.children.sort.each do |dir|
      record = convert(*documents(dir))

      assert_kind_of DDBJRecord::V3::Root, parses(record), dir.basename.to_s
      assert canonical(record), dir.basename.to_s
    end
  end

  test 'the table is the pinned spec\'s' do
    table = SPEC_FIXTURES.join('../../mapping/sra.yml')

    unless table.exist?
      flunk 'the submodule is not checked out' if ENV['REQUIRE_SPEC_SUBMODULE']

      skip 'the submodule is not checked out'
    end

    assert_equal table.read, DRA::Mapping::PATH.read, 'copy the spec\'s sra.yml to schema/ddbj-record/mapping/sra.yml'
  end

  test 'every place of the table is in the schema' do
    DRA::Mapping.rows.each_value do |rows|
      rows.each_value do |place|
        assert DRA::Schema.type_at(place), place.to_s if place.is_a?(DRA::Mapping::Place)
      end
    end
  end

  test 'a note the converter does not know refuses the table' do
    assert_raises(ArgumentError) { DRA::Mapping::Place.parse('samples[].title (要素名を大文字にした値)') }
  end

  test "a study's items all land in one project" do
    record = convert(*documents(FIXTURES.join('DRA000072')))

    assert_equal 1, record['projects'].size
    assert_equal({'accession' => 'DRP000072', 'title' => 'Whole genome analysis of Streptococcus salivarius'},
                 record['projects'].first.slice('accession', 'title'))
    assert_equal [{'type' => 'primary', 'value' => 'PRJDA43375', 'label' => 'BioProject ID'}], record['projects'].first['identifiers']
  end

  test 'sibling elements are elements of their own, and what is inside each stays there' do
    record = convert(<<~XML)
      <RUN alias="r">
        <DATA_BLOCK member_name="m">
          <FILES>
            <FILE filename="a" filetype="fastq"><READ_LABEL>F</READ_LABEL><READ_LABEL>R</READ_LABEL></FILE>
            <FILE filename="b" filetype="fastq"/>
          </FILES>
        </DATA_BLOCK>
        <DATA_BLOCK><FILES><FILE filename="c" filetype="bam"/></FILES></DATA_BLOCK>
      </RUN>
    XML

    assert_equal [
      {
        'member_name' => 'm',

        'files' => [
          {'filename' => 'a', 'filetype' => 'fastq', 'read_labels' => %w[F R]},
          {'filename' => 'b', 'filetype' => 'fastq'}
        ]
      },
      {'files' => [{'filename' => 'c', 'filetype' => 'bam'}]}
    ], record.dig('runs', 0, 'data_blocks')
  end

  test 'an item the table does not have is refused' do
    refuses '<SUBMISSION alias="s"><FOO>x</FOO></SUBMISSION>', 'SUBMISSION/FOO'
  end

  test 'an item in another namespace is not taken for SRA\'s own' do
    refuses '<SAMPLE xmlns:x="urn:x" x:alias="a"/>', 'SAMPLE/@x:alias'
  end

  test 'text where the table takes none is refused' do
    refuses '<SAMPLE alias="s"><SAMPLE_NAME>lost<TAXON_ID>9606</TAXON_ID></SAMPLE_NAME></SAMPLE>',                        'SAMPLE/SAMPLE_NAME: text'
    refuses '<SAMPLE alias="s"><SAMPLE_ATTRIBUTES><SAMPLE_ATTRIBUTE>lost<TAG>a</TAG></SAMPLE_ATTRIBUTE></SAMPLE_ATTRIBUTES></SAMPLE>', 'SAMPLE_ATTRIBUTE: text'
    refuses '<EXPERIMENT alias="e"><PLATFORM>lost</PLATFORM></EXPERIMENT>',                                            'EXPERIMENT/PLATFORM: text'
    refuses '<SUBMISSION alias="s"><ACTIONS><ACTION><ADD>lost</ADD></ACTION></ACTIONS></SUBMISSION>',                  'ACTION/ADD: text'
  end

  test 'CDATA is text, and an entity reference left unexpanded is refused' do
    assert_equal 'a <b> c', convert('<SAMPLE alias="s"><TITLE>a <![CDATA[<b>]]> c</TITLE></SAMPLE>').dig('samples', 0, 'title')

    refuses '<!DOCTYPE SAMPLE [<!ENTITY e "x">]><SAMPLE alias="s"><TITLE>a &e; b</TITLE></SAMPLE>', 'SAMPLE/TITLE: an entity reference'
  end

  test 'a set holds documents of its kind and nothing else' do
    refuses '<SAMPLE_SET center_name="c"><SAMPLE alias="s"/></SAMPLE_SET>', 'SAMPLE_SET: attributes'
    refuses '<SAMPLE_SET><EXPERIMENT alias="e"/></SAMPLE_SET>',             'SAMPLE_SET/EXPERIMENT: not a SAMPLE'
  end

  test 'a document carrying nothing of its own is refused' do
    refuses '<RUN><EXPERIMENT_REF refname="e"/></RUN>', 'RUN: a document carrying nothing'
  end

  test 'an item written twice is refused, even with the same value' do
    refuses '<SUBMISSION alias="s"><TITLE>a</TITLE><TITLE>b</TITLE></SUBMISSION>', 'title is written twice'
    refuses '<SUBMISSION alias="s"><TITLE>a</TITLE><TITLE>a</TITLE></SUBMISSION>', 'title is written twice'
  end

  test 'a HOLD without a target is the hold date, one with a target is not' do
    record = convert(<<~XML)
      <SUBMISSION alias="s">
        <ACTIONS>
          <ACTION><HOLD HoldUntilDate="2027-01-01"/></ACTION>
          <ACTION><HOLD target="DRX000001" HoldUntilDate="2026-06-01"/></ACTION>
        </ACTIONS>
      </SUBMISSION>
    XML

    assert_equal '2027-01-01', record.dig('submission', 'hold_date')
    assert_equal [{'type' => 'HOLD', 'hold_until_date' => '2027-01-01'}, {'type' => 'HOLD', 'target' => 'DRX000001', 'hold_until_date' => '2026-06-01'}],
                 record.dig('submission', 'sra', 'actions')
  end

  # ACTIONS are carried out in the order written: of the HOLDs and RELEASEs
  # naming no target, the last is the one in force.
  test 'the hold date is the last target-less HOLD, unless a RELEASE or an undated HOLD comes after it' do
    hold_date = ->(*actions) {
      convert("<SUBMISSION alias=\"s\"><ACTIONS>#{actions.map { "<ACTION>#{it}</ACTION>" }.join}</ACTIONS></SUBMISSION>").dig('submission', 'hold_date')
    }

    assert_equal '2028-01-01', hold_date.('<RELEASE/>', '<HOLD HoldUntilDate="2028-01-01"/>')
    assert_equal '2028-01-01', hold_date.('<HOLD HoldUntilDate="2027-01-01"/>', '<HOLD HoldUntilDate="2028-01-01"/>')
    assert_nil                 hold_date.('<HOLD HoldUntilDate="2027-01-01"/>', '<RELEASE/>')
    assert_nil                 hold_date.('<HOLD HoldUntilDate="2027-01-01"/>', '<HOLD HoldForPeriod="12"/>')
    assert_equal '2027-01-01', hold_date.('<HOLD HoldUntilDate="2027-01-01"/>', '<RELEASE target="DRX000001"/>')
  end

  test 'values are written as the schema types them' do
    record = convert(<<~XML)
      <EXPERIMENT alias="e">
        <DESIGN>
          <LIBRARY_DESCRIPTOR><LIBRARY_LAYOUT><PAIRED NOMINAL_LENGTH=" 300 " NOMINAL_SDEV="0.0E0"/></LIBRARY_LAYOUT></LIBRARY_DESCRIPTOR>
          <SPOT_DESCRIPTOR><SPOT_DECODE_SPEC><READ_SPEC><READ_INDEX>
            1
          </READ_INDEX></READ_SPEC></SPOT_DECODE_SPEC></SPOT_DESCRIPTOR>
        </DESIGN>
      </EXPERIMENT>
    XML

    assert_equal({'layout' => 'paired', 'nominal_length' => 300, 'nominal_sdev' => 0.0}, record.dig('experiments', 0, 'library').slice('layout', 'nominal_length', 'nominal_sdev'))
    assert_equal 1, record.dig('experiments', 0, 'spot_descriptor', 'reads', 0, 'read_index')
  end

  test 'a value the schema types is refused unless the record can hold it as written' do
    %w[two 3_00 1e3 300.0 9007199254740992].each do |value|
      refuses %(<EXPERIMENT alias="e" expected_number_runs="#{value}"/>), 'is not a integer'
    end

    %w[0x1A 1_000.5 NaN Infinity 1e400 1e-400].each do |value|
      refuses %(<EXPERIMENT alias="e"><DESIGN><LIBRARY_DESCRIPTOR><LIBRARY_LAYOUT><PAIRED NOMINAL_SDEV="#{value}"/></LIBRARY_LAYOUT></LIBRARY_DESCRIPTOR></DESIGN></EXPERIMENT>), 'is not a number'
    end
  end

  # Documents D-way stored malformed and re-read hold attribute pairs with no
  # SAMPLE_ATTRIBUTE around each: a place coming round again starts the next.
  test 'attribute pairs with no element around each are told apart' do
    record = convert(<<~XML)
      <SAMPLE alias="s">
        <SAMPLE_ATTRIBUTES>
          <TAG>a</TAG><VALUE>1</VALUE><TAG>a</TAG><VALUE>1</VALUE><TAG>a</TAG><VALUE>2</VALUE>
          <SAMPLE_ATTRIBUTE><TAG>b</TAG><VALUE>3</VALUE></SAMPLE_ATTRIBUTE>
        </SAMPLE_ATTRIBUTES>
      </SAMPLE>
    XML

    assert_equal [
      {'name' => 'a', 'value' => '1'},
      {'name' => 'a', 'value' => '1'},
      {'name' => 'a', 'value' => '2'},
      {'name' => 'b', 'value' => '3'}
    ], record.dig('samples', 0, 'attributes')
  end

  test 'a relation from an object no accession names points by alias, and by position among namesakes' do
    record = convert("<SAMPLE_SET><SAMPLE alias=\"a\">#{link('u1')}</SAMPLE><SAMPLE alias=\"b\">#{link('u2')}</SAMPLE><SAMPLE alias=\" a\">#{link('u3')}</SAMPLE></SAMPLE_SET>")

    assert_equal [{'type' => 'sample', 'alias' => 'a', 'index' => 0}, {'type' => 'sample', 'alias' => 'b'}, {'type' => 'sample', 'alias' => ' a', 'index' => 1}],
                 record['relations'].map { it['source'] }
  end

  test 'objects with no alias are namesakes of each other' do
    record = convert("<SAMPLE_SET><SAMPLE><TITLE>1</TITLE></SAMPLE><SAMPLE><TITLE>2</TITLE>#{link('u')}</SAMPLE></SAMPLE_SET>")

    assert_equal [{'type' => 'sample', 'index' => 1}], record['relations'].map { it['source'] }
  end

  test "a relation's position among namesakes names the same object once canonicalised" do
    samples = (1..4).map { "<SAMPLE alias=\"a\"><TITLE>t#{it}</TITLE>#{link("u#{it}")}</SAMPLE>" }.reverse.join
    record  = canonical(convert("<SAMPLE_SET>#{samples}</SAMPLE_SET>"))

    record['relations'].each do |relation|
      named = record['samples'].select { it['alias'] == relation.dig('source', 'alias') }.fetch(relation.dig('source', 'index'))

      assert_equal relation.dig('target', 'url').delete_prefix('u'), named['title'].delete_prefix('t')
    end
  end
end
