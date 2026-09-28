# A record checked by ddbj-validator: BioProject and BioSample, whose rules
# live there (ST.26 is checked here, DDBJRecordValidator).
#
# The check runs on the validator's side, so this starts it and then asks
# after it (PollDDBJValidatorJob) until it ends, waiting longer between asks
# the longer it runs. What the validator reports is copied into the
# validation's details as it is: one finding, one detail.
#
# A validator that cannot be asked — unreachable, not configured here, its
# run lost or ended without checking — is not something the submitter can
# fix, so the check stays running and is asked again later rather than
# failing. How long it has been waiting is what the admin screens show.
module DDBJValidatorCheck
  POLL_FIRST   = 5.seconds
  POLL_AT_MOST = 1.minute

  module_function

  def start(subject)
    validation = ActiveRecord::Base.transaction {
      subject.validating!

      # One subject, one check (see DDBJRecordValidator.validate).
      Validation.where(subject:).destroy_all

      subject.create_validation!
    }

    send_record validation
  end

  # Asked by PollDDBJValidatorJob. `attempt` counts the asks since the
  # record was last sent, for the wait before the next.
  def poll(validation, attempt)
    return unless validation.running?
    return send_record(validation) unless validation.external_id

    run = client.run(validation.external_id)

    if run.finished?
      finish validation, run.report
    elsif run.failed?
      # The run ended without checking the record; it is sent again.
      Rails.error.report DDBJValidatorClient::Unavailable.new("run #{validation.external_id} ended in error: #{run.message}")

      validation.update!(external_id: nil)
      ask_again validation, POLL_AT_MOST
    else
      ask_again validation, [POLL_FIRST * (2**attempt), POLL_AT_MOST].min, attempt + 1
    end
  rescue DDBJValidatorClient::Lost => e
    Rails.error.report e

    validation.update!(external_id: nil)
    ask_again validation, POLL_AT_MOST
  rescue DDBJValidatorClient::Unavailable => e
    Rails.error.report e

    ask_again validation, POLL_AT_MOST, attempt
  end

  def send_record(validation)
    subject = validation.subject
    uuid    = subject.ddbj_record.open {|file|
      client.start(io: file, filename: subject.ddbj_record.filename.to_s, record_db: subject.db, submitter_id: subject.user.uid)
    }

    validation.update!(external_id: uuid)
    ask_again validation, POLL_FIRST
  rescue DDBJValidatorClient::Unavailable => e
    Rails.error.report e

    ask_again validation, POLL_AT_MOST
  end

  def ask_again(validation, wait, attempt = 0)
    PollDDBJValidatorJob.set(wait:).perform_later(validation, attempt)
  end

  # The report's messages, each as a detail: its rule as the code, what it
  # is about (a sample's name) as the entry, and its level as the severity
  # — `info` (something the validator could not evaluate) as a warning,
  # the details having no other place for it.
  def finish(validation, report)
    subject = validation.subject

    ActiveRecord::Base.transaction do
      Array(report['messages']).each do |message|
        validation.details.create!(
          code:     message.fetch('id'),
          severity: message['level'] == 'error' ? :error : :warning,
          entry_id: message['object'].presence,
          message:  message['message'].presence || message.fetch('id')
        )
      end

      validation.update!(raw_result: report, progress: :finished, finished_at: Time.current)

      validation.details.error.exists? ? subject.validation_failed! : subject.ready_to_apply!
    end
  end

  def client = DDBJValidatorClient.new
end
