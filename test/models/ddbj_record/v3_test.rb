require 'test_helper'

class DDBJRecord::V3Test < ActiveSupport::TestCase
  SPEC_RECORDS = Rails.root.join('vendor/ddbj-record-specifications/tests/fixtures/v3/records')

  test 'the record has the keys the schema gives it' do
    assert_equal DDBJRecord::V3::SCHEMA.fetch('properties').keys.map(&:to_sym), DDBJRecord::V3::Root.members
    assert_includes DDBJRecord::V3::Root.members, :projects
  end

  test 'every record of the spec parses into its models' do
    skip 'the submodule is not checked out' unless SPEC_RECORDS.exist?

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
end
