# A record checked by ddbj-validator: BioProject and BioSample, whose rules
# live there (ST.26 is checked here, DDBJRecordValidator).
#
# The check runs on the validator's side, so this starts it and then asks
# after it (PollDDBJValidatorJob) until it ends, waiting longer between asks
# the longer it runs. What the validator reports is copied into the
# validation's details as it is: one finding, one detail.
#
# Every way through ends, or asks again within GIVE_UP_AFTER, so a request
# is never left checking with nothing to finish it:
#
#   - the report                    → its findings
#   - the record refused when sent  → TRD_R0015, with the validator's reason
#   - no answer in time, a run that
#     ended without checking, or no
#     validator here                → TRD_R0016, saying the file was not
#                                     checked rather than found wanting
#
# A validator that cannot be asked for a while is asked again, since that
# is nothing the submitter can fix; only when the wait runs out is the
# check ended, and the submitter can run it again.
module DDBJValidatorCheck
  POLL_FIRST   = 5.seconds
  POLL_AT_MOST = 1.minute

  # Longer than the validator gives a run (an hour), so a run it is still
  # working on is not given up on.
  GIVE_UP_AFTER = 2.hours

  REFUSED     = 'TRD_R0015'
  NOT_CHECKED = 'TRD_R0016'

  module_function

  def start(subject)
    validation = ActiveRecord::Base.transaction {
      subject.validating!

      # One subject, one check (see DDBJRecordValidator.validate).
      Validation.where(subject:).destroy_all

      subject.create_validation!
    }

    return give_up(validation, 'no ddbj-validator is configured here') unless DDBJValidatorClient.configured?

    send_record validation
  end

  # Asked by PollDDBJValidatorJob. `attempt` counts the asks since the
  # record was last sent, for the wait before the next.
  def poll(validation, attempt)
    return unless validation.running?
    return give_up(validation, "ddbj-validator had not finished within #{GIVE_UP_AFTER.inspect}") if validation.created_at < GIVE_UP_AFTER.ago
    return send_record(validation) unless validation.external_id

    run = client.run(validation.external_id)

    if run.finished? && run.report
      finish validation, run.report
    elsif run.finished? || run.failed?
      give_up validation, "the ddbj-validator run ended without a report#{": #{run.message}" if run.message.present?}"
    else
      ask_again validation, [POLL_FIRST * (2**attempt), POLL_AT_MOST].min, attempt + 1
    end
  rescue DDBJValidatorClient::Lost
    validation.update!(external_id: nil)
    ask_again validation, POLL_FIRST
  rescue DDBJValidatorClient::Unavailable
    ask_again validation, POLL_AT_MOST, attempt
  rescue StandardError => e
    Rails.error.report e, context: {validation_id: validation.id}

    ask_again validation, POLL_AT_MOST, attempt
  end

  def send_record(validation)
    subject = validation.subject
    uuid    = subject.ddbj_record.open {|file|
      client.start(io: file, filename: subject.ddbj_record.filename.to_s, record_db: subject.db, submitter_id: subject.user.uid)
    }

    validation.update!(external_id: uuid)
    ask_again validation, POLL_FIRST
  rescue DDBJValidatorClient::Refused => e
    conclude validation, [{code: REFUSED, severity: :error, message: "ddbj-validator refused the record: #{e.message}"}]
  rescue DDBJValidatorClient::Unavailable
    ask_again validation, POLL_AT_MOST
  rescue StandardError => e
    Rails.error.report e, context: {validation_id: validation.id}

    ask_again validation, POLL_AT_MOST
  end

  def ask_again(validation, wait, attempt = 0)
    PollDDBJValidatorJob.set(wait:).perform_later(validation, attempt)
  end

  # The report's messages, each as a detail: its rule as the code, what it
  # is about (a sample's name) as the entry, and its level as the severity
  # — `info` (a rule the validator could not evaluate for a record, such as
  # an umbrella's members) as a warning, the details having no other place
  # for it.
  def finish(validation, report)
    details = Array(report['messages']).map {|message|
      code = message['id'].presence || 'ddbj-validator'

      {
        code:,
        severity: message['level'] == 'error' ? :error : :warning,
        entry_id: message['object'].presence,
        message:  message['message'].presence || code
      }
    }

    conclude validation, details, report:
  end

  # Reported once, here: every ask before it that found the validator out of
  # reach is part of the same failure.
  def give_up(validation, reason)
    Rails.error.report DDBJValidatorClient::Unavailable.new(reason), context: {validation_id: validation.id}

    conclude validation, [{
      code:     NOT_CHECKED,
      severity: :error,
      message:  "The record could not be checked: #{reason}. This says nothing about the file; check it again later."
    }]
  end

  # Written under a lock on the check, and only while it is still running:
  # a check run again destroys this one, and an ask already under way must
  # not then write into it or move the request on.
  def conclude(validation, details, report: nil)
    ActiveRecord::Base.transaction do
      validation.lock!

      if validation.running?
        details.each { validation.details.create!(it) }
        validation.update!(raw_result: report, progress: :finished, finished_at: Time.current)

        subject = validation.subject
        validation.details.error.exists? ? subject.validation_failed! : subject.ready_to_apply!
      end
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def client = DDBJValidatorClient.new
end
