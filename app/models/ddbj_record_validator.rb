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
    filename   = subject.validation.subject.ddbj_record.filename.to_s
    record     = JSON.parse(subject.ddbj_record.download, symbolize_names: true)
    app_number = record.dig(:submission, :application_identification, :application_number_text)

    unless app_number&.match?(%r(\A\d{4}[-/]\d{6}\z))
      details << {
        filename:,
        entry_id: nil,
        code:     'TRD_R0001',
        severity: 'error',
        message:  'ApplicationNumberText must be in the format of yyyy-nnnnnn'
      }
    end

    Array(record.dig(:sequence, :entries)).each do |entry|
      entry_id = entry[:id]

      details.concat validate_qualifiers(entry[:source_qualifiers], **{
        filename:,
        entry_id:,
        feature:  :source
      })

      seq = entry[:sequence].to_s

      if seq.empty?
        details << {
          filename:,
          entry_id:,
          code:     'TRD_R0002',
          severity: 'error',
          message:  'Sequence length is zero'
        }
      end

      if seq.match?(/\AN+\z/i)
        details << {
          filename:,
          entry_id:,
          code:     'TRD_R0003',
          severity: 'error',
          message:  'N-only sequence is not allowed'
        }
      end

      if seq.match?(/\AX+\z/i)
        details << {
          filename:,
          entry_id:,
          code:     'TRD_R0004',
          severity: 'error',
          message:  'X-only sequence is not allowed'
        }
      end

      aa = Array(entry.dig(:source_qualifiers, :mol_type)).any? { it[:value] == 'protein' }

      if !aa && seq.match?(/[^acgtmrwsykvhdbn]/i)
        details << {
          filename:,
          entry_id:,
          code:     'TRD_R0005',
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
          filename:,
          entry_id:,
          code:     'TRD_R0006',
          severity: 'warning',
          message:  %(Undefined feature key "#{fkey}")
        }
      end

      details.concat validate_qualifiers(feature[:qualifiers], **{
        filename:,
        entry_id:,
        feature:  fkey
      })
    end
  rescue JSON::ParserError => e
    details << {
      filename:,
      entry_id: nil,
      code:     nil,
      severity: 'error',
      message:  e.message
    }
  ensure
    subject.validation.details.insert_all! details
  end

  def validate_qualifiers(quals, filename:, entry_id:, feature:)
    details = []

    Array(quals).each do |qkey, entries|
      pos = feature == :source ? 'source' : "feature=#{feature}"

      unless FeatureChecker.defined_qualifier?(qkey)
        details << {
          filename:,
          entry_id:,
          code:     'TRD_R0007',
          severity: 'warning',
          message:  %(Undefined qualifier key "#{qkey}" (#{pos}))
        }
      end

      entries.pluck(:value).each do |value|
        unless FeatureChecker.qualifier_value_presence_valid?(qkey, value)
          details << {
            filename:,
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
