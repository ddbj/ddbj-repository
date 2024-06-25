module DDBJValidator
  def validate(validation)
    validation.write_files_to_tmp do |dir|
      validation.objs.without_base.each do |obj|
        part = Faraday::Multipart::FilePart.new(dir.join(obj.path).to_s, 'application/octet-stream')

        begin
          res = client.post('validation', obj._id.downcase => part)
          validated, details = wait_for_finish(res.body.fetch(:uuid))
        rescue Faraday::Error => e
          obj.update! validity: 'error', validation_details: [
            message: e.message
          ]

          Rails.error.report e
        else
          validity = if validated
                       details.fetch(:validity) ? 'valid' : 'invalid'
                     else
                       'error'
                     end

          obj.update! validity:, validation_details: details.fetch(:messages).map {|msg|
            {
              code:     msg[:id],
              severity: msg[:level],
              message:  msg[:message]
            }
          }
        end
      end
    end
  end

  private

  def client
    @client ||= Faraday.new(url: ENV.fetch('DDBJ_VALIDATOR_URL')) {|f|
      f.request :multipart

      f.response :raise_error
      f.response :json, parser_options: {symbolize_names: true}
      f.response :logger unless Rails.env.test?
    }
  end

  def wait_for_finish(uuid)
    status = client.get("validation/#{uuid}/status")

    case status.body.fetch(:status)
    when 'accepted', 'running'
      sleep 1 unless Rails.env.test?

      wait_for_finish(uuid)
    when 'finished'
      result = client.get("validation/#{uuid}")

      [true, result.body.fetch(:result)]
    when 'error'
      result = client.get("validation/#{uuid}")

      [false, error: result.body.fetch(:message)]
    else
      raise "must not happen: #{status.body.to_json}"
    end
  end
end
