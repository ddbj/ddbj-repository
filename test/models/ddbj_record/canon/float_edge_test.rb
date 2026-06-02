require 'test_helper'

# Per schema/canon/array-modes.yml `floats:`, exactly TWO JSON pointer
# paths are permitted to carry a Float in ddbj-canon/v1:
#
#   /features/*/score
#   /experiments/*/library/nominal_sdev
#
# Every other path must be Integer (in IEEE-754 safe range) or String.
# These tests pin both the allow-list (positive cases) and the deny-list
# (FloatNotAllowedError elsewhere), plus the non-finite guard and the
# §2.3 sign / formatting rules that apply even at allowed paths.
module DDBJRecord::Canon; end

class DDBJRecord::Canon::FloatEdgeTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  test 'float accepted at /features/*/score' do
    bytes = C.canonicalize({'features' => [{'score' => 0.5}]})
    assert_equal '{"features":[{"score":0.5}]}', bytes
  end

  test 'float accepted at /experiments/*/library/nominal_sdev' do
    bytes = C.canonicalize({'experiments' => [{'library' => {'nominal_sdev' => 3.14}}]})
    assert_equal '{"experiments":[{"library":{"nominal_sdev":3.14}}]}', bytes
  end

  test 'float at unlisted path raises FloatNotAllowedError' do
    error = assert_raises C::FloatNotAllowedError do
      C.canonicalize({'foo' => 1.5})
    end

    assert_includes error.message, '/foo',
                    'error must point at the offending pointer to aid debugging'
  end

  test 'non-finite float at allowed path raises UnsupportedValueError' do
    assert_raises C::UnsupportedValueError do
      C.canonicalize({'features' => [{'score' => Float::NAN}]})
    end

    assert_raises C::UnsupportedValueError do
      C.canonicalize({'features' => [{'score' => Float::INFINITY}]})
    end

    assert_raises C::UnsupportedValueError do
      C.canonicalize({'features' => [{'score' => -Float::INFINITY}]})
    end
  end

  test 'negative zero at allowed path normalises to 0 per §2.3' do
    bytes = C.canonicalize({'features' => [{'score' => -0.0}]})

    assert_includes bytes, '"score":0',
                    "expected `\"score\":0` in #{bytes.inspect} per §2.3 sign-of-zero rule"
    refute_includes bytes, '-0',
                    'no `-0` token should survive canonicalisation'
  end

  test 'integer-valued float below 1e21 serialises without exponent' do
    # 2**60 ≈ 1.15e18, well below RFC 8785's 1e21 exponent threshold.
    bytes  = C.canonicalize({'features' => [{'score' => (2**60).to_f}]})
    score  = bytes[/"score":([^}]+)/, 1]

    refute_nil score, 'expected `"score":...` token in canonical output'
    refute_match(/[eE]/, score, 'integer-valued float below 1e21 must NOT use exponent notation')
    refute_match(/\./,   score, 'integer-valued float below 1e21 must NOT carry a fractional part')
    assert_match(/\A\d+\z/, score, 'integer-valued float must serialise as a bare integer literal')
  end
end
