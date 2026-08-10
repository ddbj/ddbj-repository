require 'test_helper'
require 'open3'

module DDBJRecord::Canon; end

# `schema/canon/v3-fields.yml` is derived by hand from the vendored spec, and
# `canon:fields_check` only compares it against the V3 Data classes. So the
# manifest and the classes can agree with each other while both have drifted
# from the spec they claim to describe — which is what happens when the
# submodule is moved with `git submodule update --remote` and the manifest is
# not regenerated, or regenerated without updating `SPEC_SHA`.
#
# This pins the three places that name a spec revision to the gitlink actually
# recorded for the submodule. Read from the index rather than the checked-out
# submodule so the check holds without `git submodule update --init` — the
# gitlink is what every other checkout resolves to anyway.
class DDBJRecord::Canon::SpecPinTest < ActiveSupport::TestCase
  SUBMODULE = 'vendor/ddbj-record-specifications'.freeze

  # `# Derived from ddbj-record-specifications @ bdcdb8d8 (2026-04-13)`
  CITATION = /ddbj-record-specifications @ (?<sha>[0-9a-f]{7,40})/

  CITING_FILES = %w[
    schema/canon/v3-fields.yml
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
                 'moving the submodule. Regenerate schema/canon/v3-fields.yml either way.'
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
