module Database::BioSample
  class Param
    def self.build(params)
      nil
    end
  end

  class Validator
    include DDBJValidator

    def translate_error(error)
      message     = error.fetch(:message)
      annotations = error.fetch(:annotation, []).index_by { _1.fetch(:key) }
      sample_name = annotations.dig("Sample name", :value)

      case error.fetch(:id)
      when "BS_R0003"
        %(The Sample title is not unique for the Sample name "#{sample_name}". Please provide a unique Sample title.)
      when "BS_R0013"
        key       = annotations.fetch("Attribute").fetch(:value)
        value     = annotations.fetch("Attribute value").fetch(:value)
        suggested = annotations.fetch("Suggested value").fetch(:suggested_value).first

        %(Invalid data format. The "#{key}" attribute value is not valid for the Sample name "#{sample_name}". Please replace "#{value}" to "#{suggested}".)
      when "BS_R0015"
        host = annotations.fetch("host").fetch(:value)

        %(Invalid host organism name. The "host" attribute value is not valid for the Sample name "#{sample_name}". Please correct "#{host}".)
      when "BS_R0045"
        organism = annotations.fetch("organism").fetch(:value)

        %(Warning about "organism" for the Sample name "#{sample_name}". Please correct "#{organism}". If applicable, the taxonomy id will be automatically filled and the organism will be corrected to the scientific name. When the organism(s) is novel, please enter proposed name(s) in the organism, leave the taxonomy id empty and submit the BioSample.)
      when "BS_R0098"
        xsd_message = annotations.fetch("message").fetch(:value)

        "#{message} #{xsd_message}"
      when "BS_R0100"
        key       = annotations.fetch("Attribute name").fetch(:value)
        value     = annotations.fetch("Attribute value").fetch(:value)
        suggested = annotations.fetch("Suggested value").fetch(:suggested_value).first

        %(Missing values are not neccesary for optional attributes. Leave values empty when there is no information. The "#{key}" attribute value is not valid for the Sample name "#{sample_name}". Please replace "#{value}" to "#{suggested}".)
      else
        message
      end
    end
  end

  class Submitter
    def submit(submission)
      # do nothing
    end
  end
end
