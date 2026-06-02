require 'test_helper'
require 'open3'
require 'tempfile'

module DDBJRecord::Canon; end

# Cross-language byte-identity check between Ruby `json-canonicalization`
# 1.0.0 (via JcsAdapter) and Python `rfc8785` 0.1.4 on the canonicalised
# tree of every record fixture.
#
# Ruby and Python don't share §2 / §3 pre-passes — only the JCS layer is
# cross-language — so the input to both sides is the post-§2 / §3 tree
# produced by Ruby's Normalizer, not the raw fixture JSON. This locks
# the JCS layer to RFC 8785 independent of which language emits the
# bytes, which is what downstream tooling (Python migration scripts,
# external auditors) needs to be able to assume.
class DDBJRecord::Canon::CrossLangJcsTest < ActiveSupport::TestCase
  RECORDS_DIR = Rails.root.join('test/fixtures/files/ddbj_record/canon/records')
  DEFAULT_PYTHON = Rails.root.join('tmp/data-migration/spike-0-3/.venv/bin/python').to_s

  PY_DUMP_SCRIPT = <<~PYTHON.freeze
    import json, sys
    import rfc8785

    with open(sys.argv[1], 'rb') as f:
        value = json.load(f)

    sys.stdout.buffer.write(rfc8785.dumps(value))
  PYTHON

  def self.python_bin
    ENV.fetch('DDBJ_CANON_PY', DEFAULT_PYTHON)
  end

  def self.rfc8785_available?
    bin = python_bin
    return false unless File.executable?(bin)

    _out, _err, status = Open3.capture3(bin, '-c', 'import rfc8785')
    status.success?
  rescue StandardError
    false
  end

  SKIP_REASON = 'rfc8785 not available — install rfc8785==0.1.4 in a venv ' \
                '(set DDBJ_CANON_PY or use tmp/data-migration/spike-0-3/.venv)'.freeze

  Dir.glob(RECORDS_DIR.join('*.json')).sort.each do |path|
    name = File.basename(path, '.json')

    define_method("test_jcs_byte_identity_#{name}") do
      skip SKIP_REASON unless self.class.rfc8785_available?

      raw    = File.read(path, encoding: Encoding::UTF_8)
      parsed = JSON.parse(raw)
      tree   = DDBJRecord::Canonicalizer::Normalizer.transform(parsed).tree

      ruby_bytes = DDBJRecord::Canonicalizer::JcsAdapter.dump(tree)
      py_bytes   = dump_via_python(tree)

      assert_equal ruby_bytes.bytesize, py_bytes.bytesize,
                   "byte length differs for #{name}: ruby=#{ruby_bytes.bytesize} python=#{py_bytes.bytesize}"
      assert_equal ruby_bytes.b, py_bytes.b,
                   "JCS output differs between ruby and python for #{name}"
    end
  end

  private

  # Write `tree` as plain JSON to a tempfile, then shell out to Python and
  # ask `rfc8785.dumps` to canonicalise it. Returns the raw stdout bytes.
  def dump_via_python(tree)
    Tempfile.create(['ddbj-canon-tree', '.json']) do |io|
      io.binmode
      io.write(JSON.generate(tree))
      io.flush

      stdout, stderr, status = Open3.capture3(
        self.class.python_bin,
        '-c',
        PY_DUMP_SCRIPT,
        io.path,
        binmode: true
      )

      assert status.success?,
             "python rfc8785 dump failed (#{status.exitstatus}): #{stderr}"

      stdout
    end
  end
end
