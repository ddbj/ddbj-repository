require 'test_helper'

# Verifies spike-0-3's 5 patch triplets against the production
# `DDBJRecord::Canonicalizer.apply` + `sha256` pipeline.
#
# Background (tmp/data-migration/spike-0-3/recommendation.md):
#   3/5 triplets round-trip cleanly. The other 2 (`smp_019635_v001_v002`,
#   `smp_020637_v001_v002`) are confirmed spike-0-1 differ artifacts —
#   the patch documents themselves are inconsistent on keyed
#   `/attributes` arrays, and BOTH Ruby `hana` and Python `jsonpatch`
#   reproduce the same wrong SHA. The patches are still structurally
#   valid RFC 6902, so `apply` should succeed; the resulting SHA must
#   simply NOT equal `sha256(after)`. If that ever changes we want a
#   loud failure, because it means our pipeline has started reproducing
#   the upstream artifact.
module DDBJRecord::Canon; end

class DDBJRecord::Canon::PatchCorpusTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  FIXTURE_DIR = Rails.root.join('test/fixtures/files/ddbj_record/canon/patch_triplets')

  KNOWN_BROKEN = %w[
    smp_019635_v001_v002
    smp_020637_v001_v002
  ].freeze

  Dir.glob(FIXTURE_DIR.join('*.json')).sort.each do |path|
    triplet = Oj.load(File.read(path), mode: :strict)
    name    = triplet.fetch('name')

    if KNOWN_BROKEN.include?(name)
      test "patch triplet #{name} is rejected (spike-0-1 differ artifact)" do
        # The patch documents themselves are inconsistent: spike-0-1 mixed
        # `a` and `b` indices when diffing `/attributes` keyed arrays. The
        # production pipeline catches the mistake one of two ways — either
        # the bag-descent guard rejects the patch at apply-time, or apply
        # succeeds but the resulting SHA differs from `after`. The MUST-NOT
        # case is silent success: the pipeline must never agree with a
        # broken patch.
        base  = triplet.fetch('base')
        after = triplet.fetch('after')
        patch = triplet.fetch('patch')

        result =
          begin
            applied_sha = C.sha256(C.apply(base, patch))
            applied_sha == C.sha256(after) ? :silent_match : :mismatch
          rescue C::Error
            :rejected
          end

        refute_equal :silent_match, result,
                     "#{name}: apply matched the after-SHA silently — the spike-0-1 differ " \
                     'artifact is no longer reproducing. Either the differ has been fixed ' \
                     'upstream (move out of KNOWN_BROKEN) or the production guards have a hole.'
      end
    else
      test "patch triplet #{name} round-trips: sha256(apply(base, patch)) == sha256(after)" do
        base  = triplet.fetch('base')
        after = triplet.fetch('after')
        patch = triplet.fetch('patch')

        applied = C.apply(base, patch)

        assert_equal C.sha256(after), C.sha256(applied),
                     "#{name}: applied SHA did not match after SHA"
      end

      test "patch triplet #{name} apply is atomic on mid-patch failure" do
        base  = triplet.fetch('base')
        patch = triplet.fetch('patch')

        snapshot_sha = C.sha256(base)

        sabotaged = patch + [
          {'op' => 'test', 'path' => '/__definitely_missing__', 'value' => 'nope'}
        ]

        assert_raises C::Error, "#{name}: sabotaged patch must raise" do
          C.apply(base, sabotaged)
        end

        assert_equal snapshot_sha, C.sha256(base),
                     "#{name}: base mutated after failed apply — atomicity violated"
      end
    end
  end

  test 'KNOWN_BROKEN entries all exist as fixtures' do
    available = Dir.glob(FIXTURE_DIR.join('*.json')).map {|p| File.basename(p, '.json') }
    missing   = KNOWN_BROKEN - available

    assert_empty missing,
                 "KNOWN_BROKEN references triplet(s) with no fixture: #{missing.inspect}"
  end
end
