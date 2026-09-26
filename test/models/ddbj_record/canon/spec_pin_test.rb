require 'test_helper'
require 'open3'

module DDBJRecord::Canon; end

# `DDBJRecord::V3::SPEC_SHA` names the spec revision the generated schema
# (schema/ddbj-record/v3.schema.json) was made from, and
# `schema/canon/array-modes.yml` cites the revision the registry was derived
# from. Both have to follow the submodule when it moves — the Canon workflow
# checks the schema itself against the submodule, and this checks the names.
#
# Read from the index rather than the checked-out submodule so the check holds
# without `git submodule update --init` — the gitlink is what every other
# checkout resolves to anyway.
class DDBJRecord::Canon::SpecPinTest < ActiveSupport::TestCase
  SUBMODULE = 'vendor/ddbj-record-specifications'.freeze

  # `# Derived from ddbj-record-specifications @ bdcdb8d8 (2026-04-13)`
  CITATION = /ddbj-record-specifications @ (?<sha>[0-9a-f]{7,40})/

  CITING_FILES = %w[
    schema/canon/array-modes.yml
  ].freeze

  # The gitlink staged for the submodule, or nil when git cannot answer —
  # a tarball export, or a checkout without the entry.
  def self.pinned_sha
    out, _err, status = Open3.capture3(
      'git', 'ls-files', '--stage', '--', SUBMODULE,
      chdir: Rails.root.to_s
    )

    return nil unless status.success?

    mode, sha, = out.split

    # 160000 is the gitlink mode; anything else means the path stopped being
    # a submodule and this test is asserting about the wrong thing.
    sha if mode == '160000'
  rescue StandardError
    nil
  end

  setup do
    @pinned = self.class.pinned_sha

    skip "cannot read the #{SUBMODULE} gitlink from git" unless @pinned
  end

  test 'SPEC_SHA matches the pinned submodule revision' do
    assert_equal @pinned, DDBJRecord::V3::SPEC_SHA,
                 'DDBJRecord::V3::SPEC_SHA disagrees with the gitlink — either the submodule ' \
                 'moved without updating the constant, or the constant was bumped without ' \
                 'moving the submodule. Regenerate schema/ddbj-record/v3.schema.json either way.'
  end

  CITING_FILES.each do |path|
    test "#{path} cites the pinned submodule revision" do
      cited = Rails.root.join(path).read[CITATION, :sha]

      assert cited, "#{path} no longer cites a spec revision — the header comment is the only " \
                    'record of which spec the registry was derived from'

      assert @pinned.start_with?(cited),
             "#{path} cites spec #{cited} but the submodule is pinned to #{@pinned}"
    end
  end
end
