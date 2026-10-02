require 'test_helper'

class DDBJValidatorCheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  VALIDATOR = 'http://validator.example.com'
  UUID      = '0f8e7c5a-1b2d-4c3e-9a8b-7c6d5e4f3a2b'

  setup do
    @request = submission_requests(:bioproject)
    @request.ddbj_record.attach(io: file_fixture('ddbj_record/bioproject_v3.json').open, filename: 'example.json', content_type: 'application/json')
  end

  def stub_start
    stub_request(:post, "#{VALIDATOR}/validation").to_return_json(body: {uuid: UUID, status: 'accepted'})
  end

  def stub_status(status, message: nil)
    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}/status").to_return_json(body: {uuid: UUID, status:, message:}.compact)
  end

  def stub_report(messages)
    stub_status 'finished'
    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}").to_return_json(body: {uuid: UUID, status: 'finished', result: {validity: messages.none? { it[:level] == 'error' }, messages:}})
  end

  def started
    stub_start

    DDBJValidatorCheck.start @request

    @request.validation
  end

  def details(validation) = validation.reload.details.order(:id).pluck(:code, :severity)

  test 'the record goes to the validator as a DDBJ Record of its database, from its submitter' do
    stub_start

    assert_enqueued_with job: PollDDBJValidatorJob do
      DDBJValidatorCheck.start @request
    end

    assert_requested :post, "#{VALIDATOR}/validation" do |request|
      request.body.match?(/name="record_db"\r\n\r\nbioproject\r\n/) &&
        request.body.match?(/name="submitter_id"\r\n\r\n#{users(:alice).uid}\r\n/) &&
        request.body.match?(/name="ddbj_record"; filename="example.json"/)
    end

    assert @request.reload.validating?
    assert_equal UUID, @request.validation.external_id
    assert @request.validation.running?
  end

  test 'what the validator reports becomes the details, and errors fail the request' do
    validation = started

    stub_report [
      {id: 'BP_R0015', level: 'error',   message: 'Publication reference is missing.', target: 'publication'},
      {id: 'BS_R0098', level: 'warning', message: 'An attribute has no value.',        object: 'sample-1'},
      {id: 'BP_R0016', level: 'info',    message: 'This rule could not be evaluated.'}
    ]

    DDBJValidatorCheck.poll validation, 0

    assert @request.reload.validation_failed?
    assert validation.reload.finished?

    assert_equal [
      ['BP_R0015', 'error',   nil,        'Publication reference is missing.'],
      ['BS_R0098', 'warning', 'sample-1', 'An attribute has no value.'],
      ['BP_R0016', 'warning', nil,        'This rule could not be evaluated.']
    ], validation.details.order(:id).pluck(:code, :severity, :entry_id, :message)

    assert_equal 'BP_R0015', validation.raw_result.dig('messages', 0, 'id')
  end

  test 'a report with no errors makes the request ready to apply' do
    validation = started

    stub_report [{id: 'BS_R0098', level: 'warning', message: 'An attribute has no value.'}]

    DDBJValidatorCheck.poll validation, 0

    assert @request.reload.ready_to_apply?
  end

  test 'a run still going is asked after again, waiting longer each time' do
    validation = started

    stub_status 'running'

    assert_enqueued_with job: PollDDBJValidatorJob, args: [validation, 3] do
      DDBJValidatorCheck.poll validation, 2
    end

    assert validation.reload.running?
  end

  # Not the submitter's to fix: the check waits rather than fails, until
  # the wait runs out — and then says the file was not checked.
  test 'a validator out of reach is asked again, until the wait runs out' do
    validation = started

    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}/status").to_return(status: 503)

    assert_enqueued_with job: PollDDBJValidatorJob do
      DDBJValidatorCheck.poll validation, 0
    end

    assert @request.reload.validating?

    validation.update_columns(created_at: (DDBJValidatorCheck::GIVE_UP_AFTER + 1.minute).ago)

    assert_no_enqueued_jobs only: PollDDBJValidatorJob do
      DDBJValidatorCheck.poll validation, 0
    end

    assert @request.reload.validation_failed?
    assert_equal [%w[TRD_R0016 error]], details(validation)
    assert_match 'This says nothing about the file', validation.details.sole.message
  end

  test 'a run the validator no longer knows is sent again, a few times' do
    validation = started

    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}/status").to_return(status: 404)

    assert_enqueued_with job: PollDDBJValidatorJob, at: DDBJValidatorCheck::POLL_AT_MOST.from_now do
      DDBJValidatorCheck.poll validation, 0
    end

    assert_nil validation.reload.external_id

    DDBJValidatorCheck.poll validation, 0

    assert_equal UUID, validation.reload.external_id
    assert_equal 2, validation.external_sends

    validation.update!(external_sends: DDBJValidatorCheck::MAX_SENDS)
    DDBJValidatorCheck.poll validation, 0

    assert_equal [%w[TRD_R0016 error]], details(validation)
    assert_match 'lost its run', validation.details.sole.message
  end

  # One that finished a minute ago is an answer, deadline or not.
  test 'past the deadline, a run already sent is still asked after once more' do
    validation = started
    validation.update_columns(created_at: (DDBJValidatorCheck::GIVE_UP_AFTER + 1.minute).ago)

    stub_report [{id: 'BS_R0098', level: 'warning', message: 'An attribute has no value.'}]
    DDBJValidatorCheck.poll validation, 0

    assert @request.reload.ready_to_apply?
  end

  # A run that crashed on the record would crash again; sending it again
  # every minute is an hour of someone else's CPU each time.
  test 'a run that ended without checking ends the check, not the file' do
    validation = started

    stub_status 'error', message: 'timed out'
    DDBJValidatorCheck.poll validation, 0

    assert @request.reload.validation_failed?
    assert_equal [%w[TRD_R0016 error]], details(validation)
    assert_match 'timed out', validation.details.sole.message
    assert_requested :post, "#{VALIDATOR}/validation", times: 1
  end

  test 'a record the validator refuses when sent ends the check with its reason' do
    stub_request(:post, "#{VALIDATOR}/validation").to_return_json(status: 413, body: {message: 'Request Entity Too Large'})

    DDBJValidatorCheck.start @request

    assert @request.reload.validation_failed?
    assert_equal [%w[TRD_R0015 error]], details(@request.validation)
    assert_match 'HTTP 413: Request Entity Too Large', @request.validation.details.sole.message
    assert_not CurationState.new(@request).unchecked?, 'refused is about the file'
  end

  # A proxy's access list or a rate limit says nothing about the record.
  test 'a refusal on the way to the validator is waited out, not blamed on the record' do
    [403, 429].each do |status|
      stub_request(:post, "#{VALIDATOR}/validation").to_return(status:)

      assert_enqueued_with job: PollDDBJValidatorJob do
        DDBJValidatorCheck.start @request
      end

      assert @request.reload.validating?, status.to_s
    end
  end

  # Anything unforeseen is asked again like an outage, so it too ends when
  # the wait runs out rather than leaving the request checking for good.
  test 'an answer that cannot be read is asked again, not left hanging' do
    validation = started

    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}/status").to_return(status: 200, body: 'not json', headers: {'Content-Type' => 'text/plain'})

    assert_enqueued_with job: PollDDBJValidatorJob do
      DDBJValidatorCheck.poll validation, 0
    end

    assert validation.reload.running?
  end

  # "Not asked" is not "passed" — nor is a report whose findings could not
  # be read.
  test 'a report without its findings, or invalid without an error, ends the check unchecked' do
    validation = started

    stub_status 'finished'
    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}").to_return_json(body: {uuid: UUID, status: 'finished', result: {validity: false, stats: {error: 3}}})
    DDBJValidatorCheck.poll validation, 0

    assert_equal [%w[TRD_R0016 error]], details(validation)

    validation = started
    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}").to_return_json(body: {uuid: UUID, status: 'finished', result: {validity: false, messages: [{id: 'BP_R0015', level: 'warning', message: 'x'}]}})
    DDBJValidatorCheck.poll validation, 0

    assert_equal [%w[TRD_R0016 error]], details(validation)
    assert CurationState.new(@request.reload).unchecked?
  end

  # Its answer goes straight to the column: a request whose own validations
  # no longer pass would otherwise be asked about for ever.
  test 'a request that no longer passes its own validations still gets its answer' do
    validation = started
    @request.update_columns(assignee_id: users(:alice).id)

    stub_report []
    DDBJValidatorCheck.poll validation, 0

    assert @request.reload.ready_to_apply?
  end

  test 'a run finished without a report ends the check' do
    validation = started

    stub_status 'finished'
    stub_request(:get, "#{VALIDATOR}/validation/#{UUID}").to_return_json(body: {uuid: UUID, status: 'finished', result: nil})

    DDBJValidatorCheck.poll validation, 0

    assert_equal [%w[TRD_R0016 error]], details(validation)
  end

  # Checking again replaces the check; an ask under way for the old one
  # must not move the request on.
  test 'an answer for a check that has been replaced writes nothing' do
    validation = started
    stale      = Validation.find(validation.id)

    stub_start
    DDBJValidatorCheck.start @request

    stub_report []
    DDBJValidatorCheck.poll stale, 0

    assert @request.reload.validating?
    assert @request.validation.running?
  end

  test 'where no validator is configured, the check ends saying so' do
    DDBJValidatorClient.stub(:configured?, false) do
      DDBJValidatorCheck.start @request
    end

    assert @request.reload.validation_failed?
    assert_match 'no ddbj-validator is configured here', @request.validation.details.sole.message
    assert_not_requested :post, "#{VALIDATOR}/validation"
  end

  # Nothing the validator could say would change these.
  test 'what only the repository can say ends the check before anything is sent' do
    record = JSON.parse(file_fixture('ddbj_record/bioproject_v3.json').read)
    record['projects'][0]['accession'] = 'PRJDB1'

    @request.ddbj_record.attach(io: StringIO.new(record.to_json), filename: 'example.json', content_type: 'application/json')

    DDBJValidatorCheck.start @request

    assert @request.reload.validation_failed?
    assert_equal [%w[TRD_R0018 error]], details(@request.validation)
    assert_equal 'project-1', @request.validation.details.sole.entry_id
    assert_not_requested :post, "#{VALIDATOR}/validation"
  end

  # The record does not change between sends, and checking a large one
  # costs a minute; an outage must not repeat it every minute.
  test 'the intake runs once, not on every send' do
    stub_request(:post, "#{VALIDATOR}/validation").to_return(status: 503)

    calls = 0
    count = lambda {|*|
      calls += 1
      []
    }

    RecordIntake.stub(:findings, count) do
      DDBJValidatorCheck.start @request
      DDBJValidatorCheck.poll @request.validation, 0
    end

    assert_equal 1, calls
    assert_requested :post, "#{VALIDATOR}/validation", times: 2
  end

  # The store not answering while the record is read ends the check as not
  # carried out, rather than leaving it checking with nothing to finish it.
  test 'an intake that cannot read the record ends the check unchecked' do
    RecordIntake.stub(:findings, ->(*) { raise Aws::S3::Errors::ServiceError.new(nil, 'down') }) do
      DDBJValidatorCheck.start @request
    end

    assert @request.reload.validation_failed?
    assert CurationState.new(@request).unchecked?
  end

  test 'ST.26 is checked here, BioProject, BioSample and DRA by the validator' do
    st26 = submission_requests(:st26)
    attach_ddbj_record st26

    ValidateDDBJRecordJob.perform_now st26

    assert st26.reload.validation.finished?
    assert_nil st26.validation.external_id

    stub_start
    ValidateDDBJRecordJob.perform_now @request

    assert_equal UUID, @request.reload.validation.external_id

    dra = submission_requests(:dra).tap { it.update_columns(status: 'waiting_validation') }
    dra.ddbj_record.attach(io: StringIO.new({schema_version: 'v3', experiments: [{alias: 'e'}]}.to_json), filename: 'dra.json', content_type: 'application/json')

    ValidateDDBJRecordJob.perform_now dra

    assert_equal UUID, dra.reload.validation.external_id
    assert_requested(:post, "#{VALIDATOR}/validation") { it.body.match?(/name="record_db"\r\n\r\ndra\r\n/) }
  end

  # --- DRA: the reads, after the metadata ---------------------------------

  def dra_started
    @request = SubmissionRequest.new(user: users(:alice), db: 'dra', status: :waiting_validation).tap { it.save!(validate: false) }
    @request.ddbj_record.attach(io: StringIO.new({schema_version: 'v3', experiments: [{alias: 'e'}]}.to_json), filename: 'dra.json', content_type: 'application/json')

    stub_start
    DDBJValidatorCheck.send_record @request.create_validation!

    @request.validation
  end

  # Hours of reading are worth it only for metadata that passed.
  test 'a DRA record whose metadata passed is held for its reads; one that failed is not' do
    validation = dra_started

    stub_report [{id: 'DRA_R0099', level: 'warning', message: 'A warning.'}]

    assert_enqueued_with job: CheckDRAReadsJob, args: [validation] do
      DDBJValidatorCheck.poll validation, 0
    end

    assert validation.reload.running?, 'held'
    assert_equal [%w[DRA_R0099 warning]], details(validation)

    failed = dra_started

    stub_report [{id: 'DRA_R0002', level: 'error', message: 'Wrong.'}]

    assert_no_enqueued_jobs only: CheckDRAReadsJob do
      DDBJValidatorCheck.poll failed, 0
    end

    assert failed.reload.finished?
    assert @request.reload.validation_failed?
  end

  # Readings run one at a time, so age alone says nothing: only a check
  # whose job is gone is given up on.
  test 'a held check whose reading stopped is ended as not carried out, one still waiting its turn is not' do
    stopped = dra_started
    waiting = dra_started

    [stopped, waiting].each { it.update_columns(raw_result: {'validity' => true}, updated_at: 1.hour.ago) }

    alive = [%([{"_aj_globalid":"#{waiting.to_global_id}"}])]

    DDBJValidatorCheck.stub(:live_reading_arguments, alive) do
      DDBJValidatorCheck.give_up_stopped_readings
    end

    assert stopped.reload.finished?
    assert_match 'the reading of its reads stopped before it ended', stopped.details.sole.message
    assert waiting.reload.running?
  end
end
