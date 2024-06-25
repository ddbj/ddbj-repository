module DDBJValidator
  def validate(validation)
    validation.write_files_to_tmp do |dir|
      validation.objs.without_base.each do |obj|
        part = Faraday::Multipart::FilePart.new(dir.join(obj.path).to_s, 'application/octet-stream')

        begin
          res        = client.post('validation', obj._id.downcase => part)
          ok, result = wait_for_finish(res.body.fetch(:uuid))
        rescue Faraday::Error => e
          obj.validity_error!

          obj.validation_details.create!(
            severity: 'error',
            message:  e.message
          )

          Rails.error.report e
        else
          # each is executed only once, so it will not be overwritten by subsequent executions
          validation.update! raw_result: result

          if ok
            obj.update! validity: result.fetch(:validity) ? 'valid' : 'invalid'

            result.fetch(:messages).each do |msg|
              code, severity, message = msg.fetch_values(:id, :level, :message)

              obj.validation_details.create! code:, severity:, message:
            end
          else
            obj.validity_error!

            obj.validation_details.create!(
              severity: 'error',
              message:  result
            )
          end
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

      [false, result.body.fetch(:message)]
    else
      raise "must not happen: #{status.body.to_json}"
    end
  end
end