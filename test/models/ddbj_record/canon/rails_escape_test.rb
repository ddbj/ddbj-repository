require 'test_helper'

# Regression: `json-canonicalization` (used by JcsAdapter) calls
# `::JSON.generate` directly, which bypasses ActiveSupport's
# `String#to_json` override. AS escapes `<`, `>`, `&` to `<`
# / `>` / `&` when `escape_html_entities_in_json = true`
# (the Rails default). The canonicalizer MUST emit raw bytes per
# RFC 8785 regardless of that setting.
#
# This project flips the AS setting to `false` in
# `config/initializers/json.rb`, but the test forces it back to
# `true` for the duration of each case so the regression catches
# a future revert or an upstream Rails behaviour change.
module DDBJRecord::Canon; end

class DDBJRecord::Canon::RailsEscapeTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  setup do
    # Rails is already eager-loaded in the test env, but assert it
    # explicitly so the test self-documents the precondition: the
    # `json-canonicalization` gem and every AS JSON override must be
    # resolved before we exercise the canonicalizer.
    Rails.application.eager_load!

    @original_escape_html = ActiveSupport::JSON::Encoding.escape_html_entities_in_json
    # Force the Rails default so the regression catches a revert of
    # `config/initializers/json.rb`. If the canonicalizer ever falls
    # back to AS-encoded strings, this is where it breaks.
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = true
  end

  teardown do
    ActiveSupport::JSON::Encoding.escape_html_entities_in_json = @original_escape_html
  end

  test 'rails default escape_html_entities_in_json is true' do
    # We just set it in `setup`; assert the round-trip so a future
    # reader sees what value the rest of the test runs against.
    assert_equal true, ActiveSupport::JSON::Encoding.escape_html_entities_in_json
  end

  test 'canonicalize emits raw < > & even with AS html-escape enabled' do
    bytes = C.canonicalize({
      'name' => 'A & B',
      'desc' => '</script>',
      'html' => '<tag>'
    })

    # Literal characters, not `<` / `>` / `&`.
    assert_includes bytes, '</script>'
    assert_includes bytes, '<tag>'
    assert_includes bytes, 'A & B'

    # Negative assertions: AS's escape sequences must NOT appear.
    refute_includes bytes, '\\u003c'
    refute_includes bytes, '\\u003e'
    refute_includes bytes, '\\u0026'
  end

  test 'byte-identical to a hand-rolled canonical JSON for an html-sensitive tree' do
    # Tree chosen so §2 / §3 transforms are all identity:
    #   - top-level keys are already sorted (a, b, c)
    #   - each string is single-line, no leading/trailing whitespace,
    #     no internal whitespace runs, ASCII-only (NFC identity)
    #   - no arrays (so no keyed/bag sort), no nulls, no empties
    # That makes the canonical output predictable byte-for-byte.
    value = {
      'a' => '<tag>',
      'b' => 'A & B',
      'c' => '</script>'
    }

    expected = '{"a":"<tag>","b":"A & B","c":"</script>"}'

    bytes = C.canonicalize(value)

    assert_equal expected, bytes
    assert_equal Encoding::UTF_8, bytes.encoding
  end

  test 'AS String#to_json still escapes — proves the override is active' do
    # Sanity check on the precondition: with the Rails default in
    # force, AS *does* escape `<`. If this assertion ever fails the
    # test above stops proving anything, so guard it explicitly.
    assert_equal '"\\u003ctag\\u003e"', '<tag>'.to_json
  end
end
