module DDBJRecordValidator
  # IUPAC nucleotide codes (upper and lower case). The sequence-character
  # checks below match against this set with String#count instead of a
  # case-insensitive regexp: a multi-MB sequence would otherwise blow past
  # Rails' 1-second Regexp.timeout and surface as a TRD_R9999 catch-all
  # ("regexp match timeout") even though the sequence is perfectly valid.
  # Keep this a plain set of letters: String#count treats a leading '^' as
  # negation and '-'/'\' as range/escape, so adding those would silently
  # change the matching semantics.
  NUCLEOTIDE_CODES = 'acgtmrwsykvhdbnACGTMRWSYKVHDBN'.freeze

  # Pre-negated form for `String#count` — "any character outside the IUPAC
  # nucleotide set" — cached so the per-entry loop below doesn't rebuild
  # the argument String on every call.
  INVALID_NUCLEOTIDE_PATTERN = "^#{NUCLEOTIDE_CODES}".freeze

  module_function

  def validate(subject)
    ActiveRecord::Base.transaction do
      subject.validating!
      subject.create_validation!
    end

    ActiveRecord::Base.transaction do
      begin
        _validate subject
      rescue Exception => e # rubocop:disable Lint/RescueException
        # StandardError 以外（SystemStackError 等）でも必ず終端状態に落とす。
        # ここで取り逃すと subject が validating のまま取り残される。
        # この rescue はトランザクション内なので、再 raise すると
        # validation_failed の書き込みごとロールバックされてしまう。記録のみ行う。
        Rails.error.report e

        subject.validation_failed!

        subject.validation.details.create!(
          code:     'TRD_R9999',
          severity: :error,
          message:  e.message
        )
      else
        if subject.validation.details.where(severity: :error).exists?
          subject.validation_failed!
        else
          subject.ready_to_apply!
        end
      end
    ensure
      subject.validation.update! progress: :finished, finished_at: Time.current
    end
  end

  def _validate(subject)
    details = []
    record  = subject.ddbj_record.open { DDBJRecord.parse(it) }
    v3      = record.is_a?(DDBJRecord::V3::Root)

    # Only the patent database gets the single-full-length-source rule; see
    # validate_source_location. Taken from the subject rather than from
    # `provenance.source_format`, which a producer fills in and which a record
    # assembled by anything other than submission-bulk-st26 may not carry.
    patent = subject.db == 'st26'

    # ST26 application identification — v2: submission.application_identification,
    # v3: submission.st26.application (per v3 St26Meta).
    app_node   = v3 ? record.submission&.st26&.application : record.submission&.application_identification
    app_number = app_node&.application_number_text

    if app_number && !app_number.match?(%r{\A[A-Za-z0-9/\-]+\z})
      details << {
        entry_id: nil,
        code:     'TRD_R0001',
        severity: 'error',
        message:  'ApplicationNumberText contains invalid characters (only alphanumeric, hyphen, and slash are allowed)'
      }
    end

    if app_number && !app_number.match?(%r(\A\d{4}[-/]\d{1,6}\z))
      details << {
        entry_id: nil,
        code:     'TRD_R0011',
        severity: 'warning',
        message:  'ApplicationNumberText is not in the expected format of yyyy-nnnnnn'
      }
    end

    # ST26 name fields (TRD_R0009: non-ASCII).
    # v2: arrays of LocalizedText; the en-only filter is what the rule
    #   intends to enforce ("the English text must be ASCII").
    # v3: applicant_name / inventor_name are bare strings whose language is
    #   the producer's choice (often the original Japanese), while
    #   applicant_name_latin / inventor_name_latin is the Latin form. The
    #   v3 equivalent of "must be ASCII" only applies to the *_latin
    #   variants. invention_titles keeps language_code per entry, so we
    #   mirror v2's en-only filter.
    st26 = v3 ? record.submission&.st26 : record.st26

    non_ascii_groups = if v3
      [
        ['applicant_name_latin', Array(st26&.applicant_name_latin)],
        ['inventor_name_latin',  Array(st26&.inventor_name_latin)],
        ['invention_titles',     Array(st26&.invention_titles).select { it.language_code == 'en' }.map(&:title)]
      ]
    else
      [
        ['applicant_names',      pluck_en_texts(st26&.applicant_names)],
        ['applicant_name_latin', st26&.applicant_name_latin],
        ['inventor_names',       pluck_en_texts(st26&.inventor_names)],
        ['inventor_name_latin',  st26&.inventor_name_latin],
        ['invention_titles',     pluck_en_texts(st26&.invention_titles)]
      ]
    end

    non_ascii_groups.each do |key, texts|
      Array(texts).each do |text|
        next if text.nil? || text.ascii_only?

        details << {
          entry_id: nil,
          code:     'TRD_R0009',
          severity: 'error',
          message:  "#{key} contains non-ASCII characters: #{text}"
        }
      end
    end

    # For v3, mol_type is hoisted to sequences.common_source.mol_type
    # (per V3::Sequences); v2 carries it per-entry inside source_features.
    common_mol_type = v3 ? record.sequences&.common_source&.mol_type : nil

    # Don't Array()-wrap the v2 path here — v2 records with a missing
    # `sequences` block used to fail loudly via NoMethodError → TRD_R9999;
    # silencing that would let a malformed v2 record reach ready_to_apply.
    entries = v3 ? Array(record.sequences&.entries) : record.sequences.entries

    entries.each do |entry|
      # v2 Entry has :id (server-extension); v3 Entry uses :alias as the
      # curator-facing identifier and falls back to :accession when alias
      # is blank (or, rarely, the empty string).
      entry_id = v3 ? (entry.alias.presence || entry.accession.presence) : entry.id

      Array(entry.source_features).each do |sf|
        details.concat validate_qualifiers(sf.source&.qualifiers || {}, **{
          entry_id:,
          feature: :source
        })
      end

      has_mol_type = common_mol_type.present? ||
                     Array(entry.source_features).any? { it.source&.mol_type }

      unless has_mol_type
        details << {
          entry_id:,
          code:     'TRD_R0010',
          severity: 'error',
          message:  'No source feature with mol_type found'
        }
      end

      seq = entry.sequence.to_s

      if seq.empty?
        details << {
          entry_id:,
          code:     'TRD_R0002',
          severity: 'error',
          message:  'Sequence length is zero'
        }
      end

      aa = common_mol_type == 'protein' ||
           Array(entry.source_features).any? { it.source&.mol_type == 'protein' }

      if !aa && !seq.empty? && seq.count('^Nn').zero?
        details << {
          entry_id:,
          code:     'TRD_R0003',
          severity: 'error',
          message:  'N-only sequence is not allowed'
        }
      end

      if aa && !seq.empty? && seq.count('^Xx').zero?
        details << {
          entry_id:,
          code:     'TRD_R0004',
          severity: 'error',
          message:  'X-only sequence is not allowed'
        }
      end

      if !aa && seq.count(INVALID_NUCLEOTIDE_PATTERN).positive?
        details << {
          entry_id:,
          code:     'TRD_R0005',
          severity: 'error',
          message:  'Invalid characters found in nucleotide sequence'
        }
      end

      # An entry states its length twice over: `length`, which LOCUS prints,
      # and the source locations, which the source lines and the REFERENCE
      # span print (Flatfile::Entry#location_span). NCBI reported the
      # disagreement as INSDC-3468 — a 20-base sequence whose source said
      # 1..21, so the flatfile claimed both.
      #
      # Refused rather than quietly corrected, in every case below. Three
      # things could be the wrong one and only the producer knows which; a
      # correction here would make the record disagree with the ST.26 file it
      # came from without anybody being told.
      #
      # `length` is a v2 server extension — v3 Entry has no such member, so
      # there the sequence is the only measure.
      declared = v3 ? nil : entry.length&.to_i
      measured = seq.size

      if declared && declared != measured
        # Checked before the locations, and instead of them: measuring a
        # location against a length that is itself wrong produces a second
        # error naming the wrong quantity.
        details << {
          entry_id:,
          code:     'TRD_R0013',
          severity: 'error',
          message:  "declared length #{declared} does not match the #{measured}-long sequence"
        }
      elsif measured.positive?
        # `declared` where it exists, per the length being what LOCUS prints
        # — the two are equal by the branch above, so this only decides which
        # number the message quotes.
        Array(entry.source_features).each do |sf|
          details.concat validate_source_location(sf.location, **{
            length:   declared || measured,
            entry_id:,
            optional: v3,
            strict:   patent
          })
        end
      end
    end

    features = v3 ? Array(record.features) : record.features

    features.each do |feature|
      fkey     = feature.type
      entry_id = feature.sequence_id

      unless FeatureChecker.defined_feature?(fkey)
        details << {
          entry_id:,
          code:     'TRD_R0006',
          severity: 'warning',
          message:  %(Undefined feature key "#{fkey}")
        }
      end

      details.concat validate_qualifiers(feature.qualifiers || {}, entry_id:, feature: fkey)
    end
  # Oj::ParseError is raised by the v2 SAJ Handler on malformed JSON.
  # TypeError is what V3::Parser raises when the JSON is well-formed
  # but a node has the wrong container type (e.g. `"sequences": []`
  # where an object is expected) — surface both as a parse error
  # detail rather than letting them escape into the outer rescue =>
  # TRD_R9999 catch-all.
  rescue Oj::ParseError, TypeError => e
    details << {
      entry_id: nil,
      code:     nil,
      severity: 'error',
      message:  e.message
    }
  ensure
    subject.validation.details.insert_all! details
  end

  # Two rules, and which one applies is a property of the database.
  #
  # Everywhere: a location may not leave the sequence. That is the defect NCBI
  # reported, and it is wrong in any database — the source line would name
  # bases that are not there.
  #
  # ST.26 only: the location must be the whole sequence exactly. PATENT-386
  # records that a patent source is a single full-length one and that anything
  # else violates the ST.26 text. Elsewhere a partial source is ordinary — the
  # v2 schema's own comment on SourceFeature describes several sources dividing
  # one entry, and a genome record carrying `1..500` and `501..1000` is
  # perfectly well formed. Applying the patent rule to those would refuse
  # valid records as Trad migration brings them in.
  #
  # Checked per feature rather than only on the one REFERENCE is taken from,
  # because the flatfile prints a source line for each of them.
  #
  # The span, not the string: `1` and `1..1` describe the same single base,
  # and rejecting one of them would be a rule about notation rather than
  # about length. `join(1..10,11..20)` over 20 bases passes for the same
  # reason — every line of the flatfile then agrees.
  def validate_source_location(location, length:, entry_id:, optional:, strict:)
    if location.blank?
      # v3 makes location optional (SourceFeature in the vendored schema); v2
      # requires it, and the renderer has nothing to print without it.
      return [] if optional

      return [{
        entry_id:,
        code:     'TRD_R0013',
        severity: 'error',
        message:  'source feature has no location'
      }]
    end

    span = Bio::Locations.new(location.to_s).span

    return [] if span == [1, length]

    outside = span.first < 1 || span.last > length

    return [] unless outside || strict

    [{
      entry_id:,
      code:     'TRD_R0013',
      severity: 'error',
      message:  if outside
                  %(source feature location "#{location}" spans #{span.join('..')} but the sequence is #{length} long)
                else
                  %(source feature location "#{location}" covers #{span.join('..')} of a #{length}-long sequence; an ST.26 patent source covers all of it)
                end
    }]
  rescue StandardError => e
    # bio-ruby cannot read it, and neither can the flatfile renderer:
    # Flatfile::Entry#location_span raises on the same input, so today such a
    # record reaches `apply` and fails there as the TRD_R9999 catch-all.
    # Reported here instead, where the message reaches the submitter.
    #
    # This is what refuses the MSS `1..E` form. That notation has no support
    # anywhere in this system — the renderer raises on it — so refusing it is
    # not a new restriction. Trad migration will have to teach both the
    # renderer and this check about it.
    [{
      entry_id:,
      code:     'TRD_R0013',
      severity: 'error',
      message:  %(source feature location "#{location}" could not be read: #{e.message})
    }]
  end

  def pluck_en_texts(array)
    Array(array).select { it.language_code == 'en' }.map(&:text)
  end

  def validate_qualifiers(quals, entry_id:, feature:)
    details = []

    quals.each do |qkey, entries|
      pos = feature == :source ? 'source' : "feature=#{feature}"

      unless FeatureChecker.defined_qualifier?(qkey)
        details << {
          entry_id:,
          code:     'TRD_R0007',
          severity: 'warning',
          message:  %(Undefined qualifier key "#{qkey}" (#{pos}))
        }
      end

      entries.map(&:value).each do |value|
        unless FeatureChecker.qualifier_value_presence_valid?(qkey, value)
          details << {
            entry_id:,
            code:     'TRD_R0008',
            severity: 'error',
            message:  %(Invalid presence of qualifier value for key "#{qkey}" (#{pos}))
          }
        end
      end
    end

    details
  end
end
