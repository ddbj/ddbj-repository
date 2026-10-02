require 'test_helper'

class SubmissionApplyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # A request as the API would leave it, ready to apply. Saved past the
  # creation rule, which refuses a DRA one.
  def request_for(db, fixture)
    SubmissionRequest.new(user: users(:alice), db:, status: :waiting_application).tap {|request|
      request.ddbj_record.attach(io: file_fixture("ddbj_record/#{fixture}").open, filename: fixture, content_type: 'application/json')
      request.save!(validate: false)
    }
  end

  test 'a BioProject record becomes a submission whose chain holds it, and its Project row' do
    request = request_for('bioproject', 'bioproject_v3.json')

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert_equal 'applied', request.status
    assert submission.bioproject_db?
    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.canonical_version

    update = submission.updates.sole

    assert_equal 'submitted',                      update.source
    assert_equal "submitter:#{users(:alice).uid}", update.actor

    assert_equal 'A project title long enough to read', submission.materialised_record.dig('projects', 0, 'title')

    project = submission.project

    assert_equal 'primary',              project.project_type
    assert_equal 'submission_accepted',  project.status
    assert_nil                           project.accession
    assert_equal 'A project title long enough to read', project.title, 'projected from the record'
  end

  # As a deploy runs again a job it had to stop after the apply committed.
  test 'a BioProject apply run again after it committed is said applied, not done twice' do
    request = request_for('bioproject', 'bioproject_v3.json')

    ApplySubmissionRequestJob.perform_now request
    request.update_columns(status: 'applying')

    assert_no_difference -> { Submission.count } do
      ApplySubmissionRequestJob.perform_now request
    end

    assert request.reload.applied?
  end

  # Solid Queue ran it again on a guess that the first run was dead, and
  # the first is still applying: it waits, since the first may yet die.
  test 'an apply does nothing while another run of the same request holds it' do
    request = request_for('bioproject', 'bioproject_v3.json')

    holding_advisory_lock "apply_submission_request:#{request.id}" do
      assert_enqueued_with job: ApplySubmissionRequestJob, args: [request] do
        ApplySubmissionRequestJob.perform_now request
      end
    end

    assert_nil request.reload.submission
    assert request.waiting_application?
  end

  test 'a BioSample record becomes Sample rows, one per sample' do
    request = request_for('biosample', 'biosample_v3.json')

    ApplySubmissionRequestJob.perform_now request

    samples = request.reload.submission.samples.order(:sample_name)

    assert_equal [
      ['sample-1', 'First sample',  'Homo sapiens', 9606,  'submission_accepted'],
      ['sample-2', 'Second sample', 'Mus musculus', 10090, 'submission_accepted']
    ], samples.pluck(:sample_name, :title, :organism, :taxonomy_id, :status)
  end

  # docs/v3-schema.md: projects and samples may travel together, each
  # registered by its own request. Each submission holds its own part only
  # — with what the record as a whole relates to, which is both parts', and
  # what starts from an object of no stated kind, which could be either's —
  # and the file as sent stays on the request.
  test 'a record carrying both databases is held by each submission as its own part' do
    bs = request_for('biosample', 'biosample_v3.json')
    bp = request_for('bioproject', 'biosample_v3.json')

    ApplySubmissionRequestJob.perform_now bs
    ApplySubmissionRequestJob.perform_now bp

    samples_side  = bs.reload.submission.materialised_record
    projects_side = bp.reload.submission.materialised_record

    assert_nil samples_side['projects']
    assert_equal({'sample' => 1, nil => 2}, samples_side['relations'].map { it.dig('source', 'type') }.tally)

    assert_nil projects_side['samples']
    assert_equal({'project' => 1, nil => 2}, projects_side['relations'].map { it.dig('source', 'type') }.tally)

    assert_equal file_fixture('ddbj_record/biosample_v3.json').read, bs.ddbj_record.download, 'the file as sent is kept as it was'
  end

  test 'a database with no Apply is refused by name' do
    assert_raises ArgumentError, match: 'gea records are not applied yet' do
      SubmissionApply.for('gea')
    end
  end

  # --- DRA ---------------------------------------------------------------

  READS = "@r1\nACGT\n+\nIIII\n"

  def upload(name, user: users(:alice))
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(READS), filename: name, content_type: 'application/octet-stream').tap {|blob|
      user.unassigned_files_attachments.create! blob:
    }
  end

  def dra_request(files, analysis_files: [], runs: [{'alias' => 'run1', 'data_blocks' => [{'files' => files}]}])
    record = {
      'schema_version' => 'v3',
      'submission'     => {'alias' => 'sub1', 'hold_date' => '2027-01-31'},
      'projects'       => [{'alias' => 'study1', 'title' => 'Not this part'}],
      'experiments'    => [{'alias' => 'exp1'}],
      'runs'           => runs,
      'analyses'       => (analysis_files.any? ? [{'alias' => 'an1', 'data_blocks' => [{'files' => analysis_files}]}] : nil),

      'relations' => [
        {'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1'}, 'target' => {'type' => 'experiment', 'alias' => 'exp1'}},
        {'type' => 'part_of', 'source' => {'type' => 'project', 'alias' => 'study1'}, 'target' => {'db' => 'bioproject', 'id' => 'PRJDB1'}},
        {'type' => 'references', 'source' => {'type' => 'submission', 'alias' => 'sub1'}, 'target' => {'db' => 'pubmed', 'id' => '1'}}
      ]
    }.compact

    SubmissionRequest.new(user: users(:alice), db: 'dra', status: :waiting_application).tap {|request|
      request.ddbj_record.attach(io: StringIO.new(record.to_json), filename: 'dra.json', content_type: 'application/json')
      request.save!(validate: false)
    }
  end

  def fastq(name) = {'filename' => name, 'filetype' => 'fastq', 'checksum_method' => 'MD5', 'checksum' => Digest::MD5.hexdigest(READS)}

  # The reads stay where they were uploaded; the submission holds the same
  # blobs, and its own part of the record. Assigned, they leave the list.
  test 'a DRA record becomes a DRASubmission, assigned the files its runs and analyses name' do
    reads    = [upload('r_1.fastq'), upload('r_2.fastq')]
    analysis = upload('a.bam')
    request  = dra_request([fastq('r_1.fastq'), fastq('r_2.fastq')], analysis_files: [fastq('a.bam')])

    ApplySubmissionRequestJob.perform_now request

    submission = request.reload.submission

    assert request.applied?
    assert submission.dra_db?
    assert_equal ['submission_accepted', nil, Date.new(2027, 1, 31)], submission.dra_submission.values_at(:status, :accession, :hold_date)
    assert_equal [*reads, analysis].sort_by(&:id), submission.data_files.blobs.order(:id).to_a
    assert_empty users(:alice).reload.unassigned_files, 'what is listed is what is still waiting'

    record = submission.materialised_record

    assert_equal %w[analyses experiments relations runs schema_version submission], record.keys.sort, 'its own part, not the study the record carries'
    assert_equal %w[run submission], record['relations'].map { it.dig('source', 'type') }.sort, 'with what starts from its submission, which is every part\'s'
  end

  # Uploaded twice, a file is two uploads, and two runs can each name one.
  test 'the same file uploaded twice can be named by two runs' do
    first, second = Array.new(2) { upload('r_1.fastq') }
    runs          = %w[run1 run2].map { {'alias' => it, 'data_blocks' => [{'files' => [fastq('r_1.fastq')]}]} }

    request = dra_request(nil, runs:)

    ApplySubmissionRequestJob.perform_now request

    assert request.reload.applied?
    assert_equal [first, second].sort_by(&:id), request.submission.data_files.blobs.order(:id).to_a
  end

  # Taken out of the list, let go of, or assigned elsewhere since the check.
  test 'a DRA record whose file has gone since its check is not applied' do
    request = dra_request([fastq('r_1.fastq')])

    assert_no_difference -> { Submission.count } do
      ApplySubmissionRequestJob.perform_now request
    end

    assert_equal %w[application_failed TRD_R0025], request.reload.values_at(:status, :error_code)
    assert_match 'runs[0] "r_1.fastq" is not among the files uploaded for it', request.error_message
  end

  # Kept in canonical order — by alias — but told where the submitter put it.
  test 'a file that has gone is named where the record as sent has it' do
    upload 'r_1.fastq'

    runs    = [{'alias' => 'zz', 'data_blocks' => [{'files' => [fastq('gone.fastq')]}]}, {'alias' => 'aa', 'data_blocks' => [{'files' => [fastq('r_1.fastq')]}]}]
    request = dra_request(nil, runs:)

    ApplySubmissionRequestJob.perform_now request

    assert_match 'runs[0] "gone.fastq"', request.reload.error_message
  end

  # Still in the list until ReleaseAssignedFilesJob takes it out, but the
  # bytes are another submission's.
  test 'an upload assigned to one submission is not assigned to another' do
    upload 'r_1.fastq'

    first, second = Array.new(2) { dra_request([fastq('r_1.fastq')]) }

    ApplySubmissionRequestJob.perform_now first
    ApplySubmissionRequestJob.perform_now second

    assert first.reload.applied?
    assert_equal %w[application_failed TRD_R0025], second.reload.values_at(:status, :error_code)
  end

  # The submission it linked went with the rolled-back transaction; writing
  # the failure must not take the link with it, or the request is left
  # applying with nothing to finish it.
  test 'an Apply that fails part way ends failed, leaving nothing behind' do
    request = request_for('biosample', 'biosample_v3.json')

    Sample.stub(:insert_all!, ->(*) { raise ActiveRecord::StatementInvalid, 'boom' }) do
      assert_no_difference -> { Submission.count + SubmissionUpdate.count + ActiveStorage::Blob.count } do
        ApplySubmissionRequestJob.perform_now request
      end
    end

    assert_equal 'application_failed', request.reload.status
    assert_equal 'TRD_R9999',          request.error_code
    assert_nil                         request.submission_id
  end
end
