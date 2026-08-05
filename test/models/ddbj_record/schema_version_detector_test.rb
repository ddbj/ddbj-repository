require 'test_helper'

class DDBJRecord::SchemaVersionDetectorTest < ActiveSupport::TestCase
  D = DDBJRecord::SchemaVersionDetector

  test 'detects v2 explicitly' do
    io           = StringIO.new('{"schema_version":"v2","submission":{}}')
    major, _head = D.detect(io)

    assert_equal '2', major
  end

  test 'detects v3 explicitly' do
    io           = StringIO.new('{"schema_version":"v3","submission":{}}')
    major, _head = D.detect(io)

    assert_equal '3', major
  end

  test 'defaults to v2 when marker absent (legacy fixtures)' do
    io           = StringIO.new('{"submission":{"comments":"hi"}}')
    major, _head = D.detect(io)

    assert_equal '2', major
  end

  test 'raises when marker absent but v3-only top-level key present' do
    io = StringIO.new('{"samples":[],"submission":{}}')

    assert_raises D::AmbiguousSchemaVersionError do
      D.detect(io)
    end
  end

  test 'raises on future major version' do
    io = StringIO.new('{"schema_version":"v9","submission":{}}')

    assert_raises D::FutureSchemaVersionError do
      D.detect(io)
    end
  end

  test 'skips a leading UTF-8 BOM' do
    io           = StringIO.new("\xEF\xBB\xBF" + '{"schema_version":"v3"}')
    major, _head = D.detect(io)

    assert_equal '3', major
  end

  test 'finds schema_version well past 4 KB (head window is 64 KB)' do
    padding = '"' + 'x' * 10_000 + '"'
    body    = %({"provenance":{"extras":#{padding}},"schema_version":"v3"})
    io      = StringIO.new(body)

    major, _head = D.detect(io)
    assert_equal '3', major
  end
end
