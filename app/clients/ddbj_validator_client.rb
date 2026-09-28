# ddbj-validator's web API (ddbj/ddbj-validator, apps/webapi): a check is
# started with the record, runs there, and is asked after until it ends.
#
#   POST /validation                ddbj_record + record_db + submitter_id → uuid
#   GET  /validation/{uuid}/status  accepted | running | finished | error
#   GET  /validation/{uuid}         the status with the report, once finished
class DDBJValidatorClient
  # The validator could not be asked: unreachable, timed out, or failing on
  # its side. Nothing about the record — the check is asked again later.
  class Unavailable < StandardError; end

  # The validator no longer knows the run (restarted, or past keeping it).
  # The check has to be started again.
  class Lost < StandardError; end

  # Where a run stands. `message` says why a run that ended in `error`
  # could not check the record; `report` is the validator's report once it
  # finished.
  Run = Data.define(:status, :message, :report) do
    def finished? = status == 'finished'
    def failed?   = status == 'error'
  end

  def self.configured? = Rails.application.config_for(:ddbj_validator).url.present?

  def initialize(config: Rails.application.config_for(:ddbj_validator))
    @config = config
  end

  # The run's uuid.
  def start(io:, filename:, record_db:, submitter_id:)
    call {
      connection.post('validation', {
        ddbj_record:  Faraday::Multipart::FilePart.new(io, 'application/json', filename),
        record_db:,
        submitter_id:
      }).body.fetch('uuid')
    }
  end

  def run(uuid)
    call(uuid) {
      status = connection.get("validation/#{uuid}/status").body

      if status['status'] == 'finished'
        body = connection.get("validation/#{uuid}").body

        Run.new(status: 'finished', message: nil, report: body.fetch('result'))
      else
        Run.new(status: status.fetch('status'), message: status['message'], report: nil)
      end
    }
  end

  private

  # An environment with no validator is one where it cannot be asked yet —
  # the same as one that is down, rather than a check that passes.
  #
  # A run the validator no longer knows is lost; any other request of ours
  # it refuses (4xx) is a mistake here, and is raised as it is; everything
  # else is the validator not answering.
  def call(uuid = nil)
    raise Unavailable, 'ddbj-validator is not configured here' if @config.url.blank?

    yield
  rescue Faraday::ResourceNotFound
    raise Lost, "run #{uuid} is not known to the validator" if uuid

    raise
  rescue Faraday::ClientError
    raise
  rescue Faraday::Error => e
    raise Unavailable, "#{e.class}: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(url: @config.url!, request: {open_timeout: 10, timeout: 300}) {|f|
      f.request  :multipart
      f.response :json
      f.response :raise_error
    }
  end
end
