# What only the repository can say about a record sent for a database whose
# rules live in ddbj-validator (BioProject, BioSample, DRA): the validator
# checks the record's content, and knows nothing of how the repository
# keeps it, or of what its submitter uploaded.
#
#   TRD_R0013  not JSON (or not UTF-8, or nested past reading)
#   TRD_R0017  not DDBJ Record v3
#   TRD_R0018  its own objects bring accessions: they are issued here
#   TRD_R0019  cannot be put in its canonical form, which is how it is kept
#   TRD_R0021  larger than can be read here (MAX_BYTES)
#   TRD_R0020  nothing of its own to register, or samples that cannot be told
#              apart: a sample is kept, found and issued its accession by its
#              alias, as it is kept (canonical, so whitespace collapsed)
#   TRD_R0022  a DRA run or analysis names a file that is not among its
#              submitter's uploads, or not with the MD5 the record states
#              (DRA::RecordFiles)
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
    'bioproject' => %w[projects],
    'biosample'  => %w[samples],
    'dra'        => %w[experiments runs analyses]
  }.freeze

  # As the pinned spec writes it (docs/versioning.md): no minor.
  V3 = 'v3'

  # What is read whole here, and put in canonical form, before the
  # validator sees it — in the job process, on the host that serves the
  # API. A record takes several times its size in memory once parsed, so
  # one of gigabytes would take the process down with it, and every other
  # job in it.
  # A BioSample record of 100,000 samples is a few hundred megabytes at
  # most; a larger one is refused before it is read.
  MAX_BYTES = 512.megabytes

  module_function

  # The findings, as validation details; empty for a record that may go on.
  def findings(subject)
    own  = OWN.fetch(subject.db) { raise ArgumentError, "no intake for #{subject.db} records" }

    if (size = subject.ddbj_record.blob.byte_size) > MAX_BYTES
      return [finding('TRD_R0021', "The record is #{ActiveSupport::NumberHelper.number_to_human_size(size)}; records of more than #{ActiveSupport::NumberHelper.number_to_human_size(MAX_BYTES)} cannot be checked here.")]
    end

    json = subject.ddbj_record.download.force_encoding(Encoding::UTF_8)

    return [finding('TRD_R0013', 'The record is not UTF-8.')] unless json.valid_encoding?

    record = Oj.load(json, mode: :strict)

    return [finding('TRD_R0017', 'The record is not a DDBJ Record v3 document (schema_version "v3").')] unless record.is_a?(Hash) && record['schema_version'] == V3

    objects(record, own).presence || accessions(record, own, subject.db).presence || files(record, subject).presence || canonical_form(record)
  rescue Oj::ParseError => e
    [finding('TRD_R0013', "The record is not JSON#{e.message[/ at (line \d+, column \d+)/, 1]&.then { " (#{it})" }}.")]
  rescue SystemStackError
    [finding('TRD_R0013', 'The record is nested too deeply to read.')]
  end

  def objects(record, own)
    unless own.any? { record[it].is_a?(Array) && record[it].any? }
      return [finding('TRD_R0020', "The record has no #{own.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')} to register.")]
    end

    return [] unless own == %w[samples]

    aliases = record['samples'].map { Sample.normalise_name(it['alias'].presence) if it.is_a?(Hash) && it['alias'].is_a?(String) }

    missing = aliases.each_index.select { aliases[it].blank? }.map {|index|
      finding('TRD_R0020', "samples[#{index}] has no alias; a sample is known by it.")
    }

    repeated = aliases.compact_blank.tally.select {|_, count| count > 1 }.keys.map {|name|
      finding('TRD_R0020', "More than one sample has the alias #{name.inspect} (spacing aside); each is known by its own.", entry_id: name)
    }

    missing + repeated
  end

  # A DRA submission is numbered too (DRA000001), where a BioProject's or
  # BioSample's is not.
  def accessions(record, own, db)
    objects  = own.flat_map {|list| Array(record[list]).each_with_index.map {|object, index| ["#{list}[#{index}]", object] } }
    objects << ['submission', record['submission']] if db == 'dra'

    objects.filter_map {|where, object|
      next unless object.is_a?(Hash) && object['accession'].present?

      finding('TRD_R0018', "#{where} carries the accession #{object['accession']}; accessions are issued by DDBJ.", entry_id: object['alias'].presence)
    }
  end

  # A DRA record's reads are uploaded before it is sent, and named in it.
  def files(record, subject)
    return [] unless subject.db == 'dra'

    DRA::RecordFiles.new(record, subject.user).unmatched.map {|entry|
      finding('TRD_R0022', "#{entry.where} #{entry.problem}.", entry_id: entry.object['alias'].presence)
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
