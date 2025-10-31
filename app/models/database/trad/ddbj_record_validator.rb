class Database::Trad::DDBJRecordValidator
  def validate(validation)
    details    = []
    obj        = validation.objs.without_base.last
    record     = JSON.parse(obj.file.download, symbolize_names: true)
    app_number = record.dig(:submission, :application_identification, :application_number_text)

    unless app_number&.match?(%r(\A\d{4}[-/]\d{6}\z))
      details << {
        code:     'SB-02001',
        severity: 'error',
        message:  'ApplicationNumberText must be in the format of yyyy-nnnnnn',
      }
    end

    Array(record.dig(:sequence, :entries)).each do |entry|
      entry_id = entry[:id]

      details.concat validate_qualifiers(entry[:source_qualifiers], obj:, entry_id:, feature: :source)

      seq = entry[:sequence].to_s

      if seq.empty?
        details << {
          entry_id:,
          code:     'SB-02006',
          severity: 'error',
          message:  'Sequence length is zero'
        }
      end

      if seq.match?(/\AN+\z/i)
        details << {
          entry_id:,
          code:     'SB-02007',
          severity: 'error',
          message:  'N-only sequence is not allowed'
        }
      end

      if seq.match?(/\AX+\z/i)
        details << {
          entry_id:,
          code:     'SB-02008',
          severity: 'error',
          message:  'X-only sequence is not allowed'
        }
      end

      aa = Array(entry.dig(:source_qualifiers, :mol_type)).any? { it[:value] == 'protein' }

      if !aa && seq.match?(/[^acgtmrwsykvhdbn]/i)
        details << {
          entry_id:,
          code:     'SB-02010',
          severity: 'error',
          message:  'Invalid characters found in nucleotide sequence'
        }
      end
    end

    Array(record[:features]).each do |feature|
      fkey     = feature[:type]
      entry_id = feature[:sequence_id]

      unless FeatureChecker.defined_feature?(fkey)
        details << {
          entry_id:,
          code:     'SB-02003',
          severity: 'warning',
          message:  %(Undefined feature key "#{fkey}")
        }
      end

      details.concat validate_qualifiers(feature[:qualifiers], obj:, entry_id:, feature: fkey)
    end
  rescue JSON::ParserError => e
    details << {
      severity: 'error',
      message:  e.message
    }
  ensure
    if details.any? { it[:severity] == 'error' }
      obj.validity_invalid!
    else
      obj.validity_valid!
    end

    obj.validation_details.insert_all! details
  end

  private

  def validate_qualifiers(quals, obj:, entry_id:, feature:)
    details = []

    Array(quals).each do |qkey, entries|
      pos = feature == :source ? 'source' : "feature=#{feature}"

      unless FeatureChecker.defined_qualifier?(qkey)
        details << {
          entry_id:,
          code:     'SB-02004',
          severity: 'warning',
          message:  %(Undefined qualifier key "#{qkey}" (#{pos}))
        }
      end

      entries.pluck(:value).each do |value|
        unless FeatureChecker.qualifier_value_presence_valid?(qkey, value)
          details << {
            entry_id:,
            code:     'SB-02005',
            severity: 'error',
            message:  %(Invalid presence of qualifier value for key "#{qkey}" (#{pos}))
          }
        end
      end
    end

    details
  end
end
