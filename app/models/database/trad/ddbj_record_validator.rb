class Database::Trad::DDBJRecordValidator
  def validate(validation)
    obj = validation.objs.without_base.last

    begin
      JSON.parse(obj.file.download)

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
