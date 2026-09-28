# What only the repository can say about a record sent for a database whose
# rules live in ddbj-validator (BioProject, BioSample): the validator checks
# the record's content, and knows nothing of how the repository keeps it.
#
#   TRD_R0013  not JSON (or not UTF-8, or nested past reading)
#   TRD_R0017  not DDBJ Record v3
#   TRD_R0018  its own objects bring accessions: they are issued here
#   TRD_R0019  cannot be put in its canonical form, which is how it is kept
#
# A record may carry more than its request's database — projects and samples
# together, the accession of the one registered first written into it
# before the other is sent (ddbj-record-specifications, docs/v3-schema.md,
# "1 つの record の範囲"). Only its own part is looked at for accessions;
# the validator likewise reads only its own.
#
# A record with any of these is not sent to the validator: none is
# something its report could change.
module RecordIntake
  # Each database's own objects — the rows it will be curated as, and so
  # the ones whose accessions the repository issues.
  OWN = {
    'bioproject' => 'projects',
    'biosample'  => 'samples'
  }.freeze

  # As the pinned spec writes it (docs/versioning.md): no minor.
  V3 = 'v3'

  module_function

  # The findings, as validation details; empty for a record that may go on.
  def findings(subject)
    own  = OWN.fetch(subject.db) { raise ArgumentError, "no intake for #{subject.db} records" }
    json = subject.ddbj_record.download.force_encoding(Encoding::UTF_8)

    return [finding('TRD_R0013', 'The record is not UTF-8.')] unless json.valid_encoding?

    record = Oj.load(json, mode: :strict)

    return [finding('TRD_R0017', 'The record is not a DDBJ Record v3 document (schema_version "v3").')] unless record.is_a?(Hash) && record['schema_version'] == V3

    accessions(record, own).presence || canonical_form(record)
  rescue Oj::ParseError => e
    [finding('TRD_R0013', "The record is not JSON#{e.message[/ at (line \d+, column \d+)/, 1]&.then { " (#{it})" }}.")]
  rescue SystemStackError
    [finding('TRD_R0013', 'The record is nested too deeply to read.')]
  end

  def accessions(record, own)
    Array(record[own]).each_with_index.filter_map {|object, index|
      next unless object.is_a?(Hash) && object['accession'].present?

      finding('TRD_R0018', "#{own}[#{index}] carries the accession #{object['accession']}; accessions are issued by DDBJ.", entry_id: object['alias'].presence)
    }
  end

  def canonical_form(record)
    DDBJRecord::Canonicalizer.canonicalize(record)

    []
  rescue DDBJRecord::Canonicalizer::Error => e
    [finding('TRD_R0019', "The record cannot be kept as it is: #{e.message}")]
  end

  def finding(code, message, entry_id: nil) = {code:, severity: :error, entry_id:, message:}
end
