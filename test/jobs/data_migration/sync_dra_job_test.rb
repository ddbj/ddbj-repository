require 'test_helper'

# What is particular to DRA. The sweep itself — resuming, counting,
# stopping on a store that is down — is SyncJob's, tested through BP.
class DataMigration::SyncDRAJobTest < ActiveJob::TestCase
  FIXTURE = Rails.root.join('test/fixtures/files/dra/DRA000072')

  class FakeStagingClient
    def initialize(rows) = @rows = rows.index_by(&:sub_id)

    def source_fingerprint = {'database' => 'drmdb'}

    def submission_ids(after: nil) = @rows.keys.sort.select { after.nil? || it > after }

    def fetch(sub_id) = @rows[sub_id]

    def close; end
  end

  def row(sub_id, accession:, documents: nil, versions: nil)
    documents ||= FIXTURE.glob('*.xml').sort_by { DRA::StagingClient::KINDS.index(it.basename.to_s.split('.')[1]) }.map(&:read)

    DRA::StagingClient::Submission.new(
      sub_id:, accession:,
      submitter_id:      'dra-submitter',
      status:            800,
      status_changed_at: nil,
      hold_date:         nil,
      dist_date:         nil,
      release_date:      nil,
      versions:          versions || [DRA::StagingClient::Version.new(saved_at: Time.zone.parse('2010-01-01'), documents:, digest: 'd')]
    )
  end

  test 'imports what was sent, and counts what was not and what did not convert' do
    rows = [
      row(1, accession: 'DRA000072'),
      row(2, accession: 'DRA000073', versions: []),
      row(3, accession: 'DRA000074', documents: ['<SAMPLE alias="x"><FOO/></SAMPLE>'])
    ]

    run = MigrationRun.create!(db: 'dra')

    DRA::StagingClient.stub(:new, FakeStagingClient.new(rows)) do
      DataMigration::SyncDRAJob.perform_now(run.id)
    end

    run.reload

    assert_equal 'completed', run.status
    assert_equal({'created' => 1, 'no_versions' => 1, 'failed' => 1}, run.counters)
    assert_match '[3] DRA::Converter::Unmapped: SAMPLE/FOO: not in the SRA mapping', run.error_log
    assert Submission.dra_db.exists?(source_id: 'DRA000072', migration_run_id: run.uuid)
  end
end
