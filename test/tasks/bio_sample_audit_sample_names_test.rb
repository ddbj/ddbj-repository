require 'test_helper'
require 'rake'

class BioSampleAuditSampleNamesTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('bio_sample:audit_sample_names')
    Rake::Task['bio_sample:audit_sample_names'].reenable

    @submission = submissions(:biosample)
    samples(:first).update!(sample_name: 'A B', accession: 'SAMD00099991')
  end

  def audit = capture_io { Rake::Task['bio_sample:audit_sample_names'].invoke }.first

  # What the TSV import did while the row said `A    B` and the record `A B`:
  # it appended a second sample under the alias.
  test 'lists a record holding a sample twice' do
    @submission.append_update!({'samples' => [{'alias' => 'A B', 'accession' => 'SAMD00099991'}]}, actor: 'test-seed')
    @submission.append_update!({'samples' => [{'alias' => 'A B', 'accession' => 'SAMD00099991'}, {'alias' => 'A    B', 'title' => 'T'}]},
                               actor: 'admin:bob', source: :tsv_import)

    assert_match(/^#{@submission.id}\t.*\ttwice\tA B$/, audit)
  end

  # What accession issuance did: the row got the accession, the record not.
  test 'lists a record lacking an accession its row was issued' do
    @submission.append_update!({'samples' => [{'alias' => 'A B'}]}, actor: 'test-seed')
    CurationEvent.record!(submission: @submission, actor: 'admin:bob', action: :accession_issued, row_count: 1)

    assert_match(/^#{@submission.id}\t.*\taccession\tSAMD00099991$/, audit)
  end

  test 'lists nothing when the record agrees with its rows' do
    @submission.append_update!({'samples' => [{'alias' => 'A B', 'accession' => 'SAMD00099991'}]}, actor: 'admin:bob', source: :tsv_import)

    assert_empty audit
  end
end
