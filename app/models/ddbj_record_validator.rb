module DDBJRecordValidator
  module_function

  def validate(subject)
    ActiveRecord::Base.transaction do
      subject.validating!
      subject.create_validation!
    end

    ActiveRecord::Base.transaction do
      begin
        _validate subject
      rescue => e
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

      if !aa && seq.match?(/\AN+\z/i)
        details << {
          entry_id:,
          code:     'TRD_R0003',
          severity: 'error',
          message:  'N-only sequence is not allowed'
        }
      end

      if aa && seq.match?(/\AX+\z/i)
        details << {
          entry_id:,
          code:     'TRD_R0004',
          severity: 'error',
          message:  'X-only sequence is not allowed'
        }
      end

      if !aa && seq.match?(/[^acgtmrwsykvhdbn]/i)
        details << {
          entry_id:,
          code:     'TRD_R0005',
          severity: 'error',
          message:  'Invalid characters found in nucleotide sequence'
        }
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
