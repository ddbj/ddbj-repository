require 'test_helper'

class SubmissionApplyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # A request as the API would leave it, ready to apply. Saved past the
  # creation rule: BioProject and BioSample are not taken yet (#2111), and
  # this is what applying one will do once they are.
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
    request = request_for('dra', 'bioproject_v3.json')

    ApplySubmissionRequestJob.perform_now request

    assert_equal 'application_failed', request.reload.status
    assert_match 'dra records are not applied yet', request.error_message
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
