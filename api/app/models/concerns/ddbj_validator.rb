module DDBJValidator
  def validate(validation)
    validation.write_files_to_tmp do |dir|
      obj  = validation.objs.without_base.sole # either BioProject or BioSample
      part = Faraday::Multipart::FilePart.new(dir.join(obj.path).to_s, "application/octet-stream")

      begin
        res      = client.post("validation", obj._id.downcase => part)
        ok, body = wait_for_finish(res.body.fetch(:uuid))
      rescue Faraday::Error => e
        obj.validity_error!

        obj.validation_details.create!(
          severity: "error",
          message:  e.message
        )

        Rails.error.report e
      else
        validation.update! raw_result: body

        if ok
          obj.update! validity: body.dig(:result, :validity) ? "valid" : "invalid"

          body.dig(:result, :messages).each do |error|
            code, severity = error.fetch_values(:id, :level)
            message        = message_for(error)

            obj.validation_details.create! code:, severity:, message:
          end
        else
          obj.validity_error!

          obj.validation_details.create!(
            severity: "error",
            message:  body.fetch(:message)
          )
        end
      end
    end
  end

  private

  def client
    @client ||= Faraday.new(url: ENV.fetch("DDBJ_VALIDATOR_URL")) { |f|
      f.request :multipart

      f.response :raise_error
      f.response :json, parser_options: { symbolize_names: true }
      f.response :logger unless Rails.env.test?
    }
  end

  def wait_for_finish(uuid)
    status = client.get("validation/#{uuid}/status")

    case status.body.fetch(:status)
    when "accepted", "running"
      sleep 1 unless Rails.env.test?

      wait_for_finish(uuid)
    when "finished"
      result = client.get("validation/#{uuid}")

      [ true, result.body ]
    when "error"
      result = client.get("validation/#{uuid}")

      [ false, result.body ]
    else
      raise "must not happen: #{status.body.to_json}"
    end
  end

  def message_for(error)
    id          = error.fetch(:id)
    message     = error.fetch(:message)
    annotations = error.fetch(:annotation, []).index_by { _1.fetch(:key) }

    case id
    when /\ABP_/
      translate_bioproject_error(id, message, annotations)
    when /\ABS_/
      translate_biosample_error(id, message, annotations)
    else
      message
    end
  end

  def translate_bioproject_error(error_id, message, annotations)
    case error_id
    when "BP_R0002"
      xsd_message = annotations.fetch("XSD error message").fetch(:value)

      "#{message} #{xsd_message}"
    else
      message
    end
  end

  def translate_biosample_error(error_id, message, annotations)
    sample_name = annotations.dig("Sample name", :value)

    case error_id
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
