class Database::BioProject::Validator
  include DDBJValidator

  def translate_error(error)
    message     = error.fetch(:message)
    annotations = error.fetch(:annotation, []).index_by { _1.fetch(:key) }

    case error.fetch(:id)
    when 'BP_R0002'
      xsd_message = annotations.fetch('XSD error message').fetch(:value)

      "#{message} #{xsd_message}"
    else
      message
    end
  end
end
