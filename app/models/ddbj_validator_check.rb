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
#   - what only the repository can
#     say (RecordIntake, once)      → its findings, before anything is sent
#   - the report                    → its findings
#   - the record refused when sent  → TRD_R0015, with the validator's reason
#   - no answer in time, a run that
#     ended without checking, or no
#     validator here                → TRD_R0016, saying the file was not
#                                     checked rather than found wanting
#
# A validator that cannot be asked for a while is asked again, since that
# is nothing the submitter can fix; only when the wait runs out is the
# check ended, and the submitter can run it again. A run given up on goes
# on at the validator, which has no way to be told to stop.
module DDBJValidatorCheck
  POLL_FIRST   = 5.seconds
  POLL_AT_MOST = 1.minute

  # Longer than the validator gives a run (an hour), so a run it is still
  # working on is not given up on.
  GIVE_UP_AFTER = 2.hours

  # How many times a record is sent before a validator that keeps losing
  # its runs is given up on.
  MAX_SENDS = 3

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

    intake validation
  end

  # What only the repository can say (RecordIntake) comes first, and once:
  # a record it would refuse anyway is not worth the validator's run, and
  # the uploaded record does not change between sends. Checking a large
  # record costs a minute, so it is not repeated on every ask.
  #
  # A failure of the intake itself (the store not answering) ends the check
  # as not carried out, for the submitter to run again, rather than leaving
  # the request checking with nothing to finish it.
  def intake(validation)
    findings = RecordIntake.findings(validation.subject)

    return conclude(validation, findings) if findings.any?
    return give_up(validation, 'no ddbj-validator is configured here') unless DDBJValidatorClient.configured?

    send_record validation
  rescue StandardError => e
    Rails.error.report e, context: {validation_id: validation.id}

    give_up validation, "the record could not be read (#{e.class})"
  end

  # Asked by PollDDBJValidatorJob. `attempt` counts the asks since the
  # record was last sent, for the wait before the next.
  #
  # Past the deadline a run already sent is still asked after once more —
  # one that finished a minute ago is an answer — and given up on only if
  # it has none.
  def poll(validation, attempt)
    return unless validation.running?

    overdue = validation.created_at < GIVE_UP_AFTER.ago

    unless validation.external_id
      return overdue ? give_up(validation, "ddbj-validator could not be reached within #{GIVE_UP_AFTER.inspect}") : send_record(validation)
    end

    run = client.run(validation.external_id)

    if run.finished? && run.report
      finish validation, run.report
    elsif run.finished? || run.failed?
      give_up validation, "the ddbj-validator run ended without a report#{": #{run.message}" if run.message.present?}"
    elsif overdue
      give_up validation, "ddbj-validator had not finished within #{GIVE_UP_AFTER.inspect}"
    else
      ask_again validation, [POLL_FIRST * (2**attempt), POLL_AT_MOST].min, attempt + 1
    end
  rescue DDBJValidatorClient::Lost
    lost validation, overdue
  rescue StandardError => e
    # Anything unforeseen is asked again like an outage, once reported;
    # the deadline ends it either way.
    Rails.error.report e, context: {validation_id: validation.id} if attempt.zero? && !e.is_a?(DDBJValidatorClient::Unavailable)

    overdue ? give_up(validation, "ddbj-validator could not be asked (#{e.class})") : ask_again(validation, POLL_AT_MOST, attempt + 1)
  end

  # A run the validator no longer knows (restarted, or cleaned up) is sent
  # again — a few times, and a minute apart, since a validator losing every
  # run would otherwise be sent the record every few seconds.
  def lost(validation, overdue)
    return give_up(validation, "ddbj-validator lost its run #{validation.external_sends} times") if validation.external_sends >= MAX_SENDS
    return give_up(validation, "ddbj-validator lost its run, and the wait of #{GIVE_UP_AFTER.inspect} ran out") if overdue

    validation.update!(external_id: nil)
    ask_again validation, POLL_AT_MOST
  end

  def send_record(validation)
    subject = validation.subject
    uuid    = subject.ddbj_record.open {|file|
      client.start(io: file, filename: subject.ddbj_record.filename.to_s, record_db: subject.db, submitter_id: subject.user.uid)
    }

    validation.update!(external_id: uuid, external_sends: validation.external_sends + 1)
    ask_again validation, POLL_FIRST
  rescue DDBJValidatorClient::Refused => e
    conclude validation, [{code: REFUSED, severity: :error, message: "ddbj-validator refused the record (#{e.message})."}]
  rescue StandardError => e
    Rails.error.report e, context: {validation_id: validation.id} unless e.is_a?(DDBJValidatorClient::Unavailable)

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
    messages = report['messages'] if report.is_a?(Hash)

    return give_up(validation, 'ddbj-validator returned a report without its findings') unless messages.is_a?(Array)

    details = messages.map {|message|
      code = message['id'].presence || 'ddbj-validator'

      {
        code:,
        severity: message['level'] == 'error' ? :error : :warning,
        entry_id: message['object'].presence,
        message:  message['message'].presence || code
      }
    }

    # A report that calls the record invalid and lists no error is one
    # whose findings were not all read — not a pass.
    if report['validity'] == false && details.none? { it[:severity] == :error }
      return give_up(validation, 'ddbj-validator reported the record invalid without saying why')
    end

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

        # Straight to the column, as `close!` and `assign!` do: a request
        # whose own validations no longer pass (its assignee stopped being
        # a curator) must still get its answer, or the check would be
        # asked again for ever.
        status = validation.details.error.exists? ? 'validation_failed' : 'ready_to_apply'
        validation.subject.update_columns(status:, updated_at: Time.current)
      end
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def client = DDBJValidatorClient.new
end
