require 'test_helper'

# Pins every record fixture's canonical SHA-256 + byte length to the
# values frozen in expected_shas.json. Any drift in Canonicalizer or its
# registry will surface here as a focused per-fixture failure.
#
# See tmp/data-migration/canonical-json.md for the wire-format spec
# (ddbj-canon/v1). The corpus is real BS records across smp_001931 /
# smp_015788 / smp_019635 / smp_020637 / smp_024372.
module DDBJRecord::Canon; end

class DDBJRecord::Canon::FixtureCorpusTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  FIXTURE_DIR = Rails.root.join('test/fixtures/files/ddbj_record/canon').freeze

  CORPUS = JSON.parse(FIXTURE_DIR.join('expected_shas.json').read).freeze

  CORPUS.each do |name, expected|
    test "fixture #{name} canonicalises to expected SHA" do
      value = JSON.parse(FIXTURE_DIR.join("records/#{name}.json").read)
      bytes = C.canonicalize(value)
      sha   = C.sha256(value)

      assert_equal expected['sha256'], sha,
                   "fixture #{name}: expected SHA #{expected['sha256']}, got #{sha}"

      assert_equal expected['bytes'], bytes.bytesize,
                   "fixture #{name}: expected #{expected['bytes']} canonical bytes, got #{bytes.bytesize}"
    end
  end
end
