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
            message        = translate_error(error)

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

  def translate_error(error)
    raise NotImplementedError
  end
end
