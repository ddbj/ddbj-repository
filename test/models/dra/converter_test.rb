require 'test_helper'

class DRA::ConverterTest < ActiveSupport::TestCase
  FIXTURES      = Rails.root.join('test/fixtures/files/dra')
  SPEC_FIXTURES = Rails.root.join('vendor/ddbj-record-specifications/tests/fixtures/v3/raw/dra')
  KINDS         = %w[submission study sample experiment run analysis].freeze

  def documents(dir) = dir.glob('*.xml').sort_by { KINDS.index(it.basename.to_s.split('.')[1]) }.map(&:read)

  def convert(*xml) = DRA::Converter.new(documents: xml).call

  def parses(record) = DDBJRecord::V3::Parser.parse(Oj.dump(record, mode: :compat))

  test 'the SRA documents of a submission become a record v3 reads' do
    FIXTURES.children.sort.each do |dir|
      assert_kind_of DDBJRecord::V3::Root, parses(convert(*documents(dir))), dir.basename.to_s
    end
  end

  test 'every raw SRA document of the spec converts' do
    # As in DDBJRecord::V3Test: the Canon workflow checks the submodule out.
    unless SPEC_FIXTURES.exist?
      flunk 'the submodule is not checked out' if ENV['REQUIRE_SPEC_SUBMODULE']

      skip 'the submodule is not checked out'
    end

    SPEC_FIXTURES.children.sort.each do |dir|
      assert_kind_of DDBJRecord::V3::Root, parses(convert(*documents(dir))), dir.basename.to_s
    end
  end

  test "a study's items all land in one project" do
    record = convert(*documents(FIXTURES.join('DRA000072')))

    assert_equal 1, record['projects'].size
    assert_equal({'accession' => 'DRP000072', 'title' => 'Whole genome analysis of Streptococcus salivarius'},
                 record['projects'].first.slice('accession', 'title'))
    assert_equal [{'type' => 'primary', 'value' => 'PRJDA43375', 'label' => 'BioProject ID'}], record['projects'].first['identifiers']
  end

  test 'an item the table does not have is refused' do
    error = assert_raises(DRA::Converter::Unmapped) { convert('<SUBMISSION alias="s"><FOO>x</FOO></SUBMISSION>') }

    assert_match 'SUBMISSION/FOO', error.message
  end

  test 'two items the table puts in one place are refused' do
    assert_raises(DRA::Converter::Unmapped) { convert('<SUBMISSION alias="s"><TITLE>a</TITLE><TITLE>b</TITLE></SUBMISSION>') }
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

  test 'numbers are written as the schema types them' do
    record = convert(<<~XML)
      <EXPERIMENT alias="e">
        <DESIGN><LIBRARY_DESCRIPTOR><LIBRARY_LAYOUT><PAIRED NOMINAL_LENGTH="300" NOMINAL_SDEV="0.0E0"/></LIBRARY_LAYOUT></LIBRARY_DESCRIPTOR></DESIGN>
      </EXPERIMENT>
    XML

    assert_equal({'layout' => 'paired', 'nominal_length' => 300, 'nominal_sdev' => 0.0}, record.dig('experiments', 0, 'library').slice('layout', 'nominal_length', 'nominal_sdev'))
  end

  test 'a number the schema types is refused when it is not one' do
    assert_raises(DRA::Converter::Unmapped) { convert('<EXPERIMENT alias="e" expected_number_runs="two"/>') }
  end

  # Documents D-way stored malformed and re-read hold attribute pairs with no
  # SAMPLE_ATTRIBUTE around each: a name coming round again starts the next.
  test 'attribute pairs with no element around each are told apart' do
    record = convert(<<~XML)
      <SAMPLE alias="s">
        <SAMPLE_ATTRIBUTES><TAG>a</TAG><VALUE>1</VALUE><TAG>b</TAG><VALUE>2</VALUE></SAMPLE_ATTRIBUTES>
      </SAMPLE>
    XML

    assert_equal [{'name' => 'a', 'value' => '1'}, {'name' => 'b', 'value' => '2'}], record.dig('samples', 0, 'attributes')
  end

  test 'a relation from an object no accession names points by alias, and by position among namesakes' do
    link   = '<SAMPLE_LINKS><SAMPLE_LINK><URL_LINK><LABEL>l</LABEL><URL>https://example.org/</URL></URL_LINK></SAMPLE_LINK></SAMPLE_LINKS>'
    record = convert("<SAMPLE_SET><SAMPLE alias=\"a\">#{link}</SAMPLE><SAMPLE alias=\"b\">#{link}</SAMPLE><SAMPLE alias=\"a\">#{link}</SAMPLE></SAMPLE_SET>")

    assert_equal [{'type' => 'sample', 'alias' => 'a', 'index' => 0}, {'type' => 'sample', 'alias' => 'b'}, {'type' => 'sample', 'alias' => 'a', 'index' => 1}],
                 record['relations'].map { it['source'] }
  end

  test 'the table is the pinned spec\'s' do
    table = SPEC_FIXTURES.join('../../mapping/sra.yml')

    unless table.exist?
      flunk 'the submodule is not checked out' if ENV['REQUIRE_SPEC_SUBMODULE']

      skip 'the submodule is not checked out'
    end

    assert_equal table.read, DRA::Mapping::PATH.read, 'copy the spec\'s sra.yml to schema/ddbj-record/mapping/sra.yml'
  end
end
