class Database::Trad::DDBJRecordValidator
  def validate(validation)
    obj        = validation.objs.without_base.last
    record     = JSON.parse(obj.file.download, symbolize_names: true)
    app_number = record.dig(:submission, :application_identification, :application_number_text)

    unless app_number&.match?(%r(\A\d{4}[-/]\d{6}\z))
      obj.validation_details.create!(
        code:     'SB-02001',
        severity: 'error',
        message:  'ApplicationNumberText must be in the format of yyyy-nnnnnn',
      )
    end

    record[:features].each do |feature|
      fkey  = feature[:type]
      seqid = feature[:sequence_id]

      unless FeatureChecker.defined_feature?(fkey)
        obj.validation_details.create!(
          code:     'SB-02003',
          severity: 'warning',
          message:  %(Undefined feature key "#{fkey}" (sequence_id=#{seqid}))
        )
      end

      feature[:qualifiers].each do |qkey, entries|
        unless FeatureChecker.defined_qualifier?(qkey)
          obj.validation_details.create!(
            code:     'SB-02004',
            severity: 'warning',
            message:  %(Undefined qualifier key "#{qkey}" (sequence_id=#{seqid}, feature=#{fkey}))
          )
        end

        entries.pluck(:value).each do |value|
          unless FeatureChecker.qualifier_value_presence_valid?(qkey, value)
            obj.validation_details.create!(
              code:     'SB-02005',
              severity: 'error',
              message:  %(Invalid presence of qualifier value for key "#{qkey}" (sequence_id=#{seqid}, feature=#{fkey}))
            )
          end
        end
      end
    end

    record.dig(:sequence, :entries).each do |entry|
      id  = entry[:id]
      seq = entry[:sequence].to_s

      if seq.empty?
        obj.validation_details.create!(
          code:     'SB-02006',
          severity: 'error',
          message:  "Sequence length is zero (id=#{id})"
        )
      end

      if seq.match?(/\AN+\z/i)
        obj.validation_details.create!(
          code:     'SB-02007',
          severity: 'error',
          message:  "N-only sequence is not allowed (id=#{id})"
        )
      end

      if seq.match?(/\AX+\z/i)
        obj.validation_details.create!(
          code:     'SB-02008',
          severity: 'error',
          message:  "X-only sequence is not allowed (id=#{id})"
        )
      end
    end
  rescue JSON::ParserError => e
    obj.validation_details.create!(
      severity: 'error',
      message:  e.message
    )
  ensure
    if obj.validation_details.any? { it.severity == 'error' }
      obj.validity_invalid!
    else
      obj.validity_valid!
    end
  end
end
