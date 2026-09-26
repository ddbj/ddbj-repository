require 'test_helper'

class DDBJRecord::V3Test < ActiveSupport::TestCase
  SPEC_RECORDS = Rails.root.join('vendor/ddbj-record-specifications/tests/fixtures/v3/records')

  test 'the record has the keys the schema gives it' do
    assert_equal DDBJRecord::V3::SCHEMA.fetch('properties').keys.map(&:to_sym), DDBJRecord::V3::Root.members
    assert_includes DDBJRecord::V3::Root.members, :projects
  end

  test 'every record of the spec parses into its models' do
    # The Canon workflow checks the submodule out for this and says so; a
    # skip there would pass without having read a single record. Elsewhere
    # (the API workflow does not check it out) the skip is expected.
    unless SPEC_RECORDS.exist?
      flunk 'the submodule is not checked out' if ENV['REQUIRE_SPEC_SUBMODULE']

      skip 'the submodule is not checked out'
    end

    SPEC_RECORDS.glob('*.json').each do |path|
      record = DDBJRecord::V3::Parser.parse(path.read)

      assert_kind_of DDBJRecord::V3::Root, record, path.basename.to_s
    end
  end

  test 'nested objects become their models, and dicts keep their keys' do
    record = DDBJRecord::V3::Parser.parse(<<~JSON)
      {"features": [{"type": "CDS", "qualifiers": {"product": [{"value": "p"}]}}], "projects": [{"relevance": {"medical": "x"}}]}
    JSON

    assert_kind_of DDBJRecord::V3::Qualifier, record.features.first.qualifiers.fetch('product').first
    assert_equal({'medical' => 'x'}, record.projects.first.relevance)
  end

  test 'a container of the wrong kind is a TypeError' do
    assert_raises(TypeError) { DDBJRecord::V3::Parser.parse('{"projects": {}}') }
  end

  # The spec forbids them (every model but Provenance), so a record carrying
  # one is not a v3 record — the pre-#11 `project`, for instance.
  test 'a key the model does not have is a TypeError' do
    assert_raises(TypeError) { DDBJRecord::V3::Parser.parse('{"project": {}}') }
    assert_kind_of DDBJRecord::V3::Root, DDBJRecord::V3::Parser.parse('{"provenance": {"anything": 1}}')
  end
end
