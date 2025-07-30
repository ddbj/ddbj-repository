using FetchRaiseError

module DDBJValidator
  def validate(validation)
    validation.write_files_to_tmp do |dir|
      obj = validation.objs.without_base.sole # either BioProject or BioSample

      begin
        res = dir.join(obj.path).open {|file|
          fetch('/validation', **{
            method: :post,

            body: Fetch::FormData.build(
              obj._id.downcase => file
            )
          })
        }

        finished, body = wait_for_finish(res.json.fetch(:uuid))
      rescue => e
        Rails.error.report e

        obj.validity_error!

        obj.validation_details.create!(
          severity: 'error',
          message:  e.message
        )
      else
        validation.update! raw_result: body

        if finished
          obj.update! validity: body.dig(:result, :validity) ? 'valid' : 'invalid'

          body.dig(:result, :messages).each do |error|
            code, severity = error.fetch_values(:id, :level)
            message        = translate_error(error)

            obj.validation_details.create! code:, severity:, message:
          end
        else
          obj.validity_error!

          obj.validation_details.create!(
            severity: 'error',
            message:  body.fetch(:message)
          )
        end
      end
    end
  end

  private

  def wait_for_finish(uuid)
    loop do
      res = fetch("/validation/#{uuid}/status")

      body   = res.json
      status = body.fetch(:status)

      case status
      when 'accepted', 'running'
        sleep 1 unless Rails.env.test?
      when 'finished', 'error'
        res = fetch("/validation/#{uuid}")

        return [status == 'finished', res.json]
      else
        raise "must not happen: #{body.to_json}"
      end
    end
  end

  def fetch(path, **options)
    Retriable.with_context(:fetch) {
      Fetch::API.fetch("#{Rails.application.config_for(:app).validator_url!}#{path}", **options).ensure_ok
    }
  end

  def translate_error(error)
    raise NotImplementedError
  end
end
