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

  # The validator refused the record when it was sent: too large (413), or
  # a request it cannot take (400, 422). The message is its own.
  class Refused < StandardError; end

  REFUSING = [400, 413, 422].freeze

  # Where a run stands. `message` says why a run that ended in `error`
  # could not check the record; `report` is the validator's report once it
  # finished.
  Run = Data.define(:status, :message, :report) do
    def finished? = status == 'finished'
    def failed?   = status == 'error'
  end

  def self.configured? = Rails.application.config_for(:ddbj_validator).url.present?

  # What ddbj-validator checks records for at all.
  RECORD_DBS = %w[bioproject biosample dra].freeze

  # The databases the validator here takes records for (config/ddbj_validator.yml),
  # of those it can: a name it cannot (a comma-separated list read as one
  # name, a database it does not check) is no database.
  def self.record_dbs = configured? ? Array(Rails.application.config_for(:ddbj_validator).record_dbs).map(&:to_s) & RECORD_DBS : []

  def initialize(config: Rails.application.config_for(:ddbj_validator))
    @config = config
  end

  # The run's uuid.
  #
  # No `submission_id`: a new record has none, and the validator reads it
  # only to keep a submission from counting as its own duplicate (BP_R0004,
  # BS_R0091). A record sent again for an applied submission will need it.
  def start(io:, filename:, record_db:, submitter_id:)
    call(refusable: true) {
      connection.post('validation', {
        ddbj_record:  Faraday::Multipart::FilePart.new(io, 'application/json', filename),
        record_db:,
        submitter_id:
      }).body.fetch('uuid')
    }
  end

  def run(uuid)
    call(uuid) {
      status = connection.get("validation/#{uuid}/status", nil, &SHORT).body

      if status['status'] == 'finished'
        body = connection.get("validation/#{uuid}", nil, &SHORT).body

        Run.new(status: 'finished', message: nil, report: body['result'])
      else
        Run.new(status: status.fetch('status'), message: status['message'], report: nil)
      end
    }
  end

  private

  # Asking after a run is quick; only sending a record — one of 100,000
  # samples — takes long. A validator that accepts and then hangs must not
  # hold a worker for as long as an upload may take.
  SHORT = ->(request) { request.options.timeout = 15 }

  # An environment with no validator is one where it cannot be asked yet —
  # the same as one that is down, rather than a check that passes.
  #
  # A run the validator no longer knows is lost; any other request of ours
  # it refuses (4xx) is a mistake here, and is raised as it is; everything
  # else is the validator not answering.
  #
  # Sending the record, only REFUSING says something about the record. The
  # other 4xx — a proxy's access list (403), a rate limit (429), a wrong url
  # (404) — say something about getting there, and are the validator out
  # of reach.
  def call(uuid = nil, refusable: false)
    raise Unavailable, 'ddbj-validator is not configured here' if @config.url.blank?

    yield
  rescue Faraday::ResourceNotFound => e
    raise Lost, "run #{uuid} is not known to the validator" if uuid

    raise Unavailable, "#{e.class}: #{e.message}"
  rescue Faraday::ClientError => e
    raise Refused, refusal_of(e) if refusable && REFUSING.include?(e.response_status)

    raise Unavailable, "#{e.class}: #{e.message}"
  rescue Faraday::Error => e
    raise Unavailable, "#{e.class}: #{e.message}"
  end

  # The body is not parsed by then (`raise_error` answers before `json`), and
  # a proxy's refusal is not JSON at all.
  def refusal_of(error)
    ["HTTP #{error.response_status}", reason_in(error.response_body)].compact.join(': ')
  end

  # The validator says why as `message`; FastAPI's own refusals (422) as a
  # list of problems under `detail`.
  def reason_in(body)
    parsed = JSON.parse(body.to_s)

    return unless parsed.is_a?(Hash)

    reason = parsed['message'] || parsed['detail']
    reason = reason.map { it.is_a?(Hash) ? it['msg'] : it }.join('; ') if reason.is_a?(Array)

    reason.to_s.presence
  rescue JSON::ParserError
    nil
  end

  def connection
    @connection ||= Faraday.new(url: @config.url!, request: {open_timeout: 10, timeout: 300}) {|f|
      f.request  :multipart
      f.response :json
      f.response :raise_error
    }
  end
end
