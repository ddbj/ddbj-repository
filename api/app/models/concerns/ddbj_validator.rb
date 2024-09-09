module DDBJValidator
  class NotOk < StandardError
    def initialize(res)
      super "#{res.status} #{res.status_text}: #{res.body}"
    end
  end

  def validate(validation)
    validation.write_files_to_tmp do |dir|
      obj = validation.objs.without_base.sole # either BioProject or BioSample

      begin
        res = dir.join(obj.path).open { |file|
          fetch("/validation", **{
            method: :post,

            body: Fetch::FormData.build(
              obj._id.downcase => file
            )
          })
        }

        finished, body = wait_for_finish(res.json.fetch(:uuid))
      rescue NotOk => e
        obj.validity_error!

        obj.validation_details.create!(
          severity: "error",
          message:  e.message
        )

        Rails.error.report e
      else
        validation.update! raw_result: body

        if finished
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

  def wait_for_finish(uuid)
    loop do
      res = fetch("/validation/#{uuid}/status")

      body   = res.json
      status = body.fetch(:status)

      case status
      when "accepted", "running"
        sleep 1 unless Rails.env.test?
      when "finished", "error"
        res = fetch("/validation/#{uuid}")

        return [ status == "finished", res.json ]
      else
        raise "must not happen: #{body.to_json}"
      end
    end
  end

  def fetch(path, **options)
    Fetch::API.fetch("#{ENV.fetch("DDBJ_VALIDATOR_URL")}#{path}", **options).tap { |res|
      raise NotOk, res unless res.ok
    }
  end

  def translate_error(error)
    raise NotImplementedError
  end
end
