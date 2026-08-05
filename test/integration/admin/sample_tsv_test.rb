require 'test_helper'

class AdminSampleTSVTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:bob)

    @submission = submissions(:biosample)
    samples(:first).update!(sample_name: 'sample-A', accession: 'SAMD00099991', status: 'curating')

    @submission.append_update!(
      {'samples' => [{'alias' => 'sample-A', 'attributes' => [{'name' => 'organism', 'value' => 'Homo sapiens'}]}]},
      actor: 'test-seed'
    )
  end

  test 'GET export streams a TSV body with the expected content type' do
    get admin_submission_sample_tsv_export_path(@submission)

    assert_response :ok
    assert_match %r{text/tab-separated-values}, response.media_type
    assert_match 'attachment',                  response.headers['Content-Disposition']
    assert_match 'sample-A',                    response.body
  end

  test 'POST create enqueues the import job and redirects to the progress page' do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("sample_name\torganism\nsample-A\tMus musculus\n"),
      'text/tab-separated-values',
      original_filename: 'edited.tsv'
    )

    assert_enqueued_with(job: ImportSampleTSVJob) do
      assert_difference 'SampleTSVImport.count', 1 do
        post admin_submission_sample_tsv_imports_path(@submission), params: {file: file}
      end
    end

    import = SampleTSVImport.last
    assert_redirected_to admin_submission_sample_tsv_import_path(@submission, import)
    assert_equal users(:bob).uid, import.actor
  end

  test 'GET error_report downloads the failure TSV; alerts when none' do
    import = @submission.sample_tsv_imports.create!(
      actor:        'bob',
      status:       'completed',
      total:        1,
      failed:       1,
      started_at:   1.minute.ago,
      finished_at:  Time.current,
      error_report: "sample_name\terror\nsample-X\tunknown sample_name\n"
    )

    get error_report_admin_submission_sample_tsv_import_path(@submission, import)
    assert_response :ok
    assert_match 'sample-X', response.body

    bare = @submission.sample_tsv_imports.create!(
      actor: 'bob', status: 'completed', started_at: 1.minute.ago, finished_at: Time.current
    )
    get error_report_admin_submission_sample_tsv_import_path(@submission, bare)
    assert_redirected_to admin_submission_sample_tsv_import_path(@submission, bare)
    assert_match(/No error report/, flash[:alert])
  end

  test 'POST requires admin auth' do
    sign_in_as users(:carol)
    post admin_submission_sample_tsv_imports_path(@submission),
         params: {file: Rack::Test::UploadedFile.new(StringIO.new("x\n"), 'text/tab-separated-values', original_filename: 'a.tsv')}

    assert_response :forbidden
  end
end
