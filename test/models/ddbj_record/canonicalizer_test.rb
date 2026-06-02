require 'test_helper'

class DDBJRecord::CanonicalizerTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  test 'sorts object keys per JCS' do
    bytes = C.canonicalize({'z' => 1, 'a' => 2, 'm' => 3})
    assert_equal '{"a":2,"m":3,"z":1}', bytes
  end

  test 'drops null/empty values per §2.5' do
    bytes = C.canonicalize({
      'title'   => 'Sample 1',
      'desc'    => '',
      'hold'    => nil,
      'tags'    => [],
      'extras'  => {},
      'count'   => 0,
      'enabled' => false
    })

    assert_equal '{"count":0,"enabled":false,"title":"Sample 1"}', bytes
  end

  test 'normalises strings — NFC, line endings, whitespace' do
    # café in NFD (e + combining acute) should fold to NFC
    nfd  = "café"
    nfc  = "café"
    refute_equal nfc, nfd

    out = C.canonicalize({'name' => nfd})
    assert_equal %({"name":"#{nfc}"}), out

    multiline = C.canonicalize({'description' => "Foo\r\n\r\nbar  "})
    assert_equal %({"description":"Foo\\n\\nbar"}), multiline
  end

  test 'sorts /samples by alias (keyed)' do
    bytes = C.canonicalize({'samples' => [{'alias' => 'B'}, {'alias' => 'A'}, {'alias' => 'C'}]})
    assert_equal '{"samples":[{"alias":"A"},{"alias":"B"},{"alias":"C"}]}', bytes
  end

  test 'sorts /experiments by content hash (bag)' do
    a = {'id' => 'X'}
    b = {'id' => 'Y'}

    one = C.canonicalize({'experiments' => [a, b]})
    two = C.canonicalize({'experiments' => [b, a]})
    assert_equal one, two
  end

  test 'rejects empty element in ordered array' do
    assert_raises C::OrderedEmptyElementError do
      C.canonicalize({'submission' => {'submitters' => [{}, {'name' => 'Alice'}]}})
    end
  end

  test 'rejects forbidden control character' do
    assert_raises C::ControlCharacterError do
      C.canonicalize({'name' => "abc\x01def"})
    end
  end

  test 'strip_volatile removes provenance / accession / schema_version' do
    input = {
      'schema_version' => 'v3',
      'provenance'     => {'source_format' => 'xml'},
      'submission'     => {'comments' => 'hello'},
      'samples'        => [{'alias' => 'A', 'accession' => 'SAMD000123'}]
    }

    stripped = C.strip_volatile(input)

    refute stripped.key?('schema_version')
    refute stripped.key?('provenance')
    assert_equal 'hello', stripped.dig('submission', 'comments')
    refute stripped['samples'][0].key?('accession')
    assert_equal 'A', stripped['samples'][0]['alias']
  end

  test 'sha256 matches Digest::SHA256.hexdigest of canonical bytes' do
    v = {'a' => 1, 'b' => 'x'}
    assert_equal Digest::SHA256.hexdigest(C.canonicalize(v)), C.sha256(v)
  end

  test 'sequence-class strings strip ws and lowercase' do
    bytes = C.canonicalize({'sequences' => {'entries' => [{'sequence' => "AcGt\nNNN\n"}]}})

    assert_includes bytes, '"sequence":"acgtnnn"'
  end

  test 'rejects sequence with non-IUPAC byte' do
    assert_raises C::SequenceAlphabetError do
      C.canonicalize({'sequences' => {'entries' => [{'sequence' => 'acgtx'}]}})
    end
  end

  test 'diff produces add/remove/replace only' do
    a   = {'project' => {'description' => 'one'}}
    b   = {'project' => {'description' => 'two', 'keywords' => ['kw1']}}
    ops = C.diff(a, b)

    assert_includes ops, {'op' => 'replace', 'path' => '/project/description', 'value' => 'two'}
    ops.each {|op| assert_includes %w[add remove replace], op['op'] }
  end

  test 'apply round-trips a basic patch' do
    base  = {'submission' => {'comments' => 'old'}}
    patch = [{'op' => 'replace', 'path' => '/submission/comments', 'value' => 'new'}]

    out = C.apply(base, patch)
    assert_equal 'new', out.dig('submission', 'comments')
  end

  test 'apply is atomic on failure' do
    base  = {'a' => 1}
    patch = [
      {'op' => 'replace', 'path' => '/a',           'value' => 2},
      {'op' => 'replace', 'path' => '/does/exist',  'value' => 9}
    ]

    assert_raises C::Error do
      C.apply(base, patch)
    end

    assert_equal 1, base['a']
  end

  test 'rejects patch path descending into bag interior' do
    patch = [{'op' => 'replace', 'path' => '/experiments/0/title', 'value' => 'X'}]
    assert_raises C::BagPatchPathError do
      C.diff({'experiments' => [{'title' => 'A'}]}, {'experiments' => [{'title' => 'X'}]}).then {|ops|
        # If diff produced this op type, apply should reject it. We force the
        # check by calling apply with the raw forbidden op directly.
        C.apply({'experiments' => [{'title' => 'A'}]}, patch)
      }
    end
  end

  test 'accepts v3 Data instances via coerce' do
    person = DDBJRecord::V3::Person.new(
      first:        'Alice',
      last:         'Lovelace',
      email:        'a@example.com',
      orcid:        nil,
      organization: nil,
      role:         nil
    )

    bytes = C.canonicalize({'people' => [person]})
    assert_includes bytes, '"first":"Alice"'
    assert_includes bytes, '"last":"Lovelace"'
  end

  test 'rejects floats by default' do
    assert_raises C::FloatNotAllowedError do
      C.canonicalize({'score' => 1.5})
    end
  end

  test 'rejects integers outside IEEE-754 safe range' do
    assert_raises C::IntegerOutOfRangeError do
      C.canonicalize({'big' => (2**60)})
    end
  end
end
