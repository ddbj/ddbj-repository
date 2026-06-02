require 'test_helper'

# Locks in RFC 8785 §3.2.3 — object keys sort by UTF-16 code units, NOT by
# Unicode codepoint. The two sort orders diverge whenever a non-BMP key sits
# next to a BMP key whose codepoint is >= 0xD800 (i.e. above the leading
# surrogate range): the BMP key's single 16-bit unit is numerically larger
# than the non-BMP key's leading surrogate (0xD800-0xDBFF), so the non-BMP
# key sorts FIRST under UTF-16 even though its codepoint is larger.
#
# Discriminating pair used here:
#   - U+FF21 "Ａ" (fullwidth A)            → UTF-16 = 0xFF21
#   - U+10000 "𐀀" (Linear B syllable B008) → UTF-16 = 0xD800 0xDC00
#
# Codepoint order : 0xFF21  < 0x10000  → "Ａ" first, "𐀀" second
# UTF-16 unit order: 0xD800 < 0xFF21   → "𐀀" first, "Ａ" second
module DDBJRecord::Canon; end

class DDBJRecord::Canon::NonBmpKeyTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  FULLWIDTH_A = "\u{FF21}".freeze  # BMP, single 16-bit unit 0xFF21
  LINEAR_B    = "\u{10000}".freeze # non-BMP, surrogate pair (0xD800, 0xDC00)

  test 'sorts object keys by UTF-16 code units, not by codepoint' do
    bytes = C.canonicalize({FULLWIDTH_A => 1, LINEAR_B => 2})

    expected = %({"#{LINEAR_B}":2,"#{FULLWIDTH_A}":1})
    assert_equal expected, bytes,
                 'non-BMP key (leading surrogate 0xD800) must sort before BMP key 0xFF21 ' \
                 'per RFC 8785 §3.2.3 UTF-16 code-unit order'

    assert_operator bytes.index(LINEAR_B), :<, bytes.index(FULLWIDTH_A),
                    'non-BMP key must appear before BMP key in the canonical output'
  end

  test 'canonical bytes are valid UTF-8 with no broken sequences' do
    bytes = C.canonicalize({FULLWIDTH_A => 1, LINEAR_B => 2})

    assert_equal Encoding::UTF_8, bytes.encoding,
                 'canonicalize must emit a String tagged as UTF-8'
    assert bytes.valid_encoding?,
           'canonical bytes must be a well-formed UTF-8 sequence (no lone surrogates)'

    assert_includes bytes.b, "\xF0\x90\x80\x80".b,
                    'non-BMP character must be emitted as 4-byte UTF-8, not CESU-8 surrogates'
  end
end
