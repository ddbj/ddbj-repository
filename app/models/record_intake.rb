# What only the repository can say about a record sent for a database whose
# rules live in ddbj-validator (BioProject, BioSample): the validator checks
# the record's content, and knows nothing of the request it came in or of
# how the repository keeps it.
#
#   TRD_R0013  not JSON
#   TRD_R0017  not DDBJ Record v3
#   TRD_R0018  carries the parts of another database (samples on a
#              BioProject request): a request is for one database
#   TRD_R0019  brings accessions of its own: they are issued here
#   TRD_R0020  cannot be put in its canonical form, which is how it is kept
#
# A record with any of these is not sent to the validator: none is
# something its report could change.
module RecordIntake
  # The parts a record for each database may carry besides its own objects.
  SHARED = %w[schema_version provenance submission relations].freeze

  # Each database's own objects — the rows it will be curated as, and so
  # the ones whose accessions the repository issues.
  OWN = {
    'bioproject' => 'projects',
    'biosample'  => 'samples'
  }.freeze

  V3 = /\Av3(\.\d+)?\z/

  module_function

  # The findings, as validation details; empty for a record that may go on.
  def findings(subject)
    record = subject.ddbj_record.open { Oj.load(it.read, mode: :strict) }

    return [finding('TRD_R0017', 'The record is not a DDBJ Record v3 document.')] unless record.is_a?(Hash) && V3.match?(record['schema_version'].to_s)

    own = OWN.fetch(subject.db)

    [*foreign_parts(record, own, subject.db), *accessions(record, own)].presence || canonical_form(record)
  rescue Oj::ParseError, EncodingError => e
    [finding('TRD_R0013', "The record is not JSON: #{e.message}")]
  end

  def foreign_parts(record, own, db)
    foreign = record.keys - SHARED - [own]

    return [] if foreign.empty?

    [finding('TRD_R0018', "A #{Submission.db_label(db)} record carries only #{own} and #{SHARED.join(', ')}; this one also carries #{foreign.sort.join(', ')}.")]
  end

  def accessions(record, own)
    Array(record[own]).each_with_index.filter_map {|object, index|
      next unless object.is_a?(Hash) && object['accession'].present?

      finding('TRD_R0019', "#{own}[#{index}] carries the accession #{object['accession']}; accessions are issued by DDBJ.", entry_id: object['alias'].presence)
    }
  end

  def canonical_form(record)
    DDBJRecord::Canonicalizer.canonicalize(record)

    []
  rescue DDBJRecord::Canonicalizer::Error => e
    [finding('TRD_R0020', "The record cannot be kept as it is: #{e.message}")]
  end

  def finding(code, message, entry_id: nil) = {code:, severity: :error, entry_id:, message:}
end
