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
    nfd  = 'café'
    nfc  = 'café'
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

  # The membership rule is volatility, not authorship (canonical-json.md
  # §4.1): a regeneration artifact goes, durable state stays. `accession`
  # is archive-assigned but never changes between regenerations, so it is
  # durable state and survives — that is the v1 → v2 delta.
  test 'strip_volatile removes regeneration artifacts but keeps accession' do
    input = {
      'schema_version' => 'v3',
      'provenance'     => {'source_format' => 'xml'},
      'submission'     => {'comments' => 'hello'},
      'samples'        => [{'alias' => 'A', 'accession' => 'SAMD000123', 'last_update' => '2026-01-01'}]
    }

    stripped = C.strip_volatile(input)

    refute stripped.key?('schema_version')
    refute stripped.key?('provenance')
    refute stripped['samples'][0].key?('last_update')
    assert_equal 'hello',       stripped.dig('submission', 'comments')
    assert_equal 'A',           stripped['samples'][0]['alias']
    assert_equal 'SAMD000123',  stripped['samples'][0]['accession']
  end

  # The point of the v2 bump: issuing an accession has to be expressible as
  # a patch, or the chain cannot claim to be the record's history.
  test 'an accession-only change produces a patch' do
    before = {'project' => {'title' => 'x'}}
    after  = {'project' => {'title' => 'x', 'accession' => 'PRJDB1'}}

    ops = C.diff(before, after)

    assert_equal [{'op' => 'add', 'path' => '/project/accession', 'value' => 'PRJDB1'}], ops
  end

  # `diff` emits array indices into the CANONICAL ordering, while `apply`
  # is pure RFC 6902 against whatever it is handed. Anything stored as a
  # root snapshot must therefore already be canonical, or every later patch
  # names the wrong element of a keyed array — silently, and only where the
  # input order happened to differ from the key order.
  test 'canonical_tree puts keyed arrays in the order diff indexes into' do
    raw = {'samples' => [{'alias' => 'zz'}, {'alias' => 'aa'}]}

    assert_equal %w[zz aa], raw['samples'].map { it['alias'] }, 'precondition: input is not in key order'
    assert_equal %w[aa zz], C.canonical_tree(raw)['samples'].map { it['alias'] }
  end

  # Storage keeps volatile fields (§4.2) — canonical_tree is `for_diff:
  # false`, so a root snapshot does not lose provenance or accession.
  test 'canonical_tree retains volatile fields' do
    tree = C.canonical_tree({'schema_version' => 'v3', 'project' => {'accession' => 'PRJDB1'}})

    assert_equal 'v3',      tree['schema_version']
    assert_equal 'PRJDB1',  tree.dig('project', 'accession')
  end

  test 'a patch applied to a canonical tree lands on the element it names' do
    stored = C.canonical_tree({'samples' => [{'alias' => 'zz'}, {'alias' => 'aa'}]})
    wanted = stored.deep_dup
    wanted['samples'].find { it['alias'] == 'aa' }['accession'] = 'SAMD1'

    result = C.apply(stored, C.diff(stored, wanted))

    assert_equal 'SAMD1', result['samples'].find { it['alias'] == 'aa' }['accession']
    assert_nil            result['samples'].find { it['alias'] == 'zz' }['accession']
  end

  # The property the chain exists for, over the operations that actually
  # reshape a keyed array.
  test 'diff then apply reproduces the target across adds, removes and edits' do
    before = C.canonical_tree({'samples' => [{'alias' => 'a', 'title' => 'A'},
                                             {'alias' => 'b', 'title' => 'B'},
                                             {'alias' => 'c', 'title' => 'C'}]})

    after = C.canonical_tree({'samples' => [{'alias' => 'a', 'title' => 'A'},
                                            {'alias' => 'c', 'title' => 'C2'},
                                            {'alias' => 'd', 'title' => 'D'}]})

    assert_equal after, C.apply(before, C.diff(before, after))
  end

  test 'the wire identifier and the registry agree on the version' do
    assert_equal DDBJRecord::Canonicalizer::Registry.canonical_version, C::VERSION
    assert_equal "ddbj-canon/v#{C::NUMBER}",                            C::VERSION
  end

  test 'strip_volatile honours index-targeted volatile path in arrays' do
    DDBJRecord::Canonicalizer::Registry.stub(:volatile_paths, ['/items/0']) do
      input    = {'items' => [{'id' => 'a'}, {'id' => 'b'}]}
      stripped = DDBJRecord::Canonicalizer.strip_volatile(input)

      assert_equal [{'id' => 'b'}], stripped['items'], 'element 0 must be filtered'
    end
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

  test 'bag-descent guard does NOT fire on unregistered (default-bag) OBJECT prefixes' do
    # Pre-fix bug: `PathClassifier.array_mode` returns the default `'bag'`
    # for ANY unregistered pointer including OBJECT prefixes like
    # `/submission`. The guard walked every prefix and saw `/submission`
    # as bag, rejecting otherwise-fine patches that just happened to
    # descend through an unregistered hash key. Switching to
    # `explicit_bag?` (only true when REGISTERED as bag) fixes it.
    #
    # Pin the regression with the actual production trigger: extending
    # `/submission/comments` (ordered) from one element to two emits
    # `add /submission/comments/1`, whose prefix walk hits `/submission`
    # along the way.
    ops = C.diff(
      {'submission' => {'comments' => ['first']}},
      {'submission' => {'comments' => %w[first second]}}
    )

    assert_equal 1, ops.size
    assert_equal 'add',                       ops[0]['op']
    assert_equal '/submission/comments/1',    ops[0]['path']
    assert_equal 'second',                    ops[0]['value']
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

  test 'accepts floats at registry-listed paths' do
    bytes = C.canonicalize({
      'features' => [
        {'type' => 'CDS', 'score' => 0.97}
      ]
    })

    assert_includes bytes, '"score":0.97'
  end

  test 'rejects integers outside IEEE-754 safe range' do
    assert_raises C::IntegerOutOfRangeError do
      C.canonicalize({'big' => (2**60)})
    end
  end

  test 'diff strips volatile sub-trees before diffing' do
    a = {'submission' => {'comments' => 'hello'}, 'schema_version' => 'v3', 'provenance' => {'source_format' => 'xml'}}
    b = {'submission' => {'comments' => 'hello'}, 'schema_version' => 'v3', 'provenance' => {'source_format' => 'json'}}

    assert_empty C.diff(a, b), 'curator content unchanged, only volatile differs — diff must be empty'
  end

  test 'apply does not rewrite untouched fields' do
    base  = {'project' => {'description' => "Foo\r\n\r\nbar  "}, 'submission' => {'comments' => 'old'}}
    patch = [{'op' => 'replace', 'path' => '/submission/comments', 'value' => 'new'}]

    out = C.apply(base, patch)

    assert_equal "Foo\r\n\r\nbar  ",  out.dig('project', 'description'), 'untouched field must keep raw bytes'
    assert_equal 'new',                out.dig('submission', 'comments')
  end

  test 'reject_bag_descent allows read-only test op against bag interior' do
    base  = {'experiments' => [{'title' => 'A'}]}
    patch = [{'op' => 'test', 'path' => '/experiments/0/title', 'value' => 'A'}]

    # `test` is read-only and must not raise BagPatchPathError; Hana itself
    # decides whether the assertion holds.
    assert_nothing_raised do
      C.apply(base, patch)
    end
  end

  test 'reject_bag_descent catches trailing empty segment' do
    base  = {'experiments' => [{'id' => 'e1'}]}
    patch = [{'op' => 'add', 'path' => '/experiments/0/', 'value' => 'sneaky'}]

    assert_raises C::BagPatchPathError do
      C.apply(base, patch)
    end
  end

  test 'reject_bag_descent catches move whose path descends into bag interior' do
    base  = {'experiments' => [{'title' => 'A'}], 'tmp' => 'X'}
    patch = [{'op' => 'move', 'from' => '/tmp', 'path' => '/experiments/0/title'}]

    assert_raises C::BagPatchPathError do
      C.apply(base, patch)
    end
  end

  test 'reject_bag_descent catches copy whose from descends into bag interior' do
    base  = {'experiments' => [{'title' => 'A'}], 'tmp' => nil}
    patch = [{'op' => 'copy', 'from' => '/experiments/0/title', 'path' => '/tmp'}]

    assert_raises C::BagPatchPathError do
      C.apply(base, patch)
    end
  end
end
