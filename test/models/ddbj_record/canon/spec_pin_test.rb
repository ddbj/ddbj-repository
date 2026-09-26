require 'test_helper'
require 'open3'

module DDBJRecord::Canon; end

# `schema/canon/array-modes.yml` cites the spec revision the registry was
# derived from. It has to follow the submodule when it moves — re-deriving
# the registry — as the generated schema does (the Canon workflow checks
# that one against the submodule itself).
#
# Read from the index rather than the checked-out submodule so the check holds
# without `git submodule update --init` — the gitlink is what every other
# checkout resolves to anyway.
class DDBJRecord::Canon::SpecPinTest < ActiveSupport::TestCase
  SUBMODULE = 'vendor/ddbj-record-specifications'.freeze

  # `# Derived from ddbj-record-specifications @ 47cd4433 (2026-09-26)`
  CITATION = /ddbj-record-specifications @ (?<sha>[0-9a-f]{7,40})/

  REGISTRY = 'schema/canon/array-modes.yml'.freeze

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

  test 'the registry cites the pinned submodule revision' do
    cited = Rails.root.join(REGISTRY).read[CITATION, :sha]

    assert cited, "#{REGISTRY} no longer cites a spec revision — the header comment is the only " \
                  'record of which spec the registry was derived from'

    assert @pinned.start_with?(cited),
           "#{REGISTRY} cites spec #{cited} but the submodule is pinned to #{@pinned}"
  end
end
