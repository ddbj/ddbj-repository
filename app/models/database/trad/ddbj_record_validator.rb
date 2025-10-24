class Database::Trad::DDBJRecordValidator
  def validate(validation)
    obj = validation.objs.without_base.last

    begin
      file = JSON.parse(obj.file.download, symbolize_names: true)

      unless file.dig(:submission, :application_identification, :application_number_text).match?(%r(\A\d{4}[-/]\d{6}\z))
        obj.validation_details.create!(
          code:     'SB-02001',
          severity: 'error',
          message:  'ApplicationNumberText must be in the format of yyyy-nnnnnn',
        )
      end

      obj.validity_valid! if obj.validation_details.empty?
    rescue JSON::ParserError => e
      obj.validity_invalid!

      obj.validation_details.create!(
        severity: 'error',
        message:  e.message
      )
    end
  end
end
