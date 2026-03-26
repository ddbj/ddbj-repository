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
    details    = []
    record     = subject.ddbj_record.open { DDBJRecord.parse(it) }
    app_number = record.submission&.application_identification&.application_number_text

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

    [
      ['applicant_names',      pluck_en_texts(record.st26&.applicant_names)],
      ['applicant_name_latin', record.st26&.applicant_name_latin],
      ['inventor_names',       pluck_en_texts(record.st26&.inventor_names)],
      ['inventor_name_latin',  record.st26&.inventor_name_latin],
      ['invention_titles',     pluck_en_texts(record.st26&.invention_titles)]
    ].each do |key, texts|
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

    record.sequences.entries.each do |entry|
      entry_id = entry.id

      entry.source_features.each do |sf|
        details.concat validate_qualifiers(sf.source&.qualifiers || {}, **{
          entry_id:,
          feature: :source
        })
      end

      unless entry.source_features.any? { it.source&.mol_type }
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

      aa = entry.source_features.any? { it.source&.mol_type == 'protein' }

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

    record.features.each do |feature|
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

      details.concat validate_qualifiers(feature.qualifiers, entry_id:, feature: fkey)
    end
  rescue Oj::ParseError => e
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
