require 'test_helper'

class DataMigration::SyncBpJobTest < ActiveJob::TestCase
  XML_FIXTURE = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB000604.xml').freeze

  class FakeStagingClient
    Submission = Struct.new(:psub_id, :submitter_id, :status_id, :accession, :project_type, :xml, :release_date, :dist_date, :modified_date, keyword_init: true)

    def initialize(rows)
      @rows = rows.index_by(&:psub_id)
      @closed = false
    end

    def submission_ids(after: nil, limit: nil)
      ids = @rows.keys.sort
      ids = ids.select {|id| id > after } if after
      ids = ids.take(limit) if limit

      ids
    end

    def fetch(psub_id)
      @rows[psub_id]
    end

    def close
      @closed = true
    end

    attr_reader :closed
  end

  def make_row(psub_id, accession: 'PRJDB502')
    FakeStagingClient::Submission.new(
      psub_id:      psub_id,
      submitter_id: 'migration-test',
      status_id:    700,
      accession:    accession,
      project_type: 'primary',
      xml:          File.read(XML_FIXTURE)
    )
  end

  test 'happy path: imports every row, reconciles total to actual counters, marks completed' do
    rows = [
      make_row('PSUB001', accession: 'PRJDB901'),
      make_row('PSUB002', accession: 'PRJDB902')
    ]
    fake = FakeStagingClient.new(rows)

    run = MigrationRun.create!(db: 'bioproject')

    BioProject::StagingClient.stub(:new, fake) do
      DataMigration::SyncBpJob.perform_now(run.id)
    end

    run.reload
    assert_equal 'completed', run.status
    # Total is reconciled to counters_total at completion (the staging set
    # can drift during a long sweep; we trust the count we actually observed).
    assert_equal 2, run.total
    assert_equal 2, run.counters_total
    assert_equal 2, run.counters.fetch('created')
    assert_not_nil run.started_at
    assert_not_nil run.finished_at
    assert fake.closed, 'StagingClient must be closed even on the success path'
  end

  test 'row with blank XML increments :no_xml without invoking the importer' do
    row = FakeStagingClient::Submission.new(
      psub_id:      'PSUB099',
      submitter_id: 'migration-test',
      status_id:    700,
      accession:    nil,
      project_type: 'primary',
      xml:          ''
    )
    fake = FakeStagingClient.new([row])

    run = MigrationRun.create!(db: 'bioproject')

    BioProject::StagingClient.stub(:new, fake) do
      DataMigration::SyncBpJob.perform_now(run.id)
    end

    run.reload
    assert_equal 'completed', run.status
    assert_equal 1, run.counters.fetch('no_xml')
  end

  test 'row that raises a non-connection error is counted :failed and logged' do
    fake = FakeStagingClient.new([make_row('PSUB001')])

    run = MigrationRun.create!(db: 'bioproject')

    BioProject::StagingClient.stub(:new, fake) do
      BioProject::Importer.stub(:new, ->(**) { raise 'boom' }) do
        DataMigration::SyncBpJob.perform_now(run.id)
      end
    end

    run.reload
    assert_equal 'completed', run.status, 'a row-level error must NOT mark the run :failed'
    assert_equal 1, run.counters.fetch('failed')
    assert_match(/\[PSUB001\] RuntimeError: boom/, run.error_log)
  end

  # One dead store is one fault, not one fault per row. The June 2026
  # sweep absorbed 15,657 identical NotFound failures and ran to the end
  # to reach the conclusion its first row already had.
  #
  # And it says storage: ActiveStorage raises the same NotFound for "the
  # blob is gone" as for "there is nothing to ask", and taking the
  # obvious reading is what made that fortnight a fortnight.
  test 'a storage failure stops the sweep instead of failing every row' do
    fake = FakeStagingClient.new([make_row('PSUB001'), make_row('PSUB002'), make_row('PSUB003')])

    run = MigrationRun.create!(db: 'bioproject')
    seen = []

    BioProject::StagingClient.stub(:new, fake) do
      BioProject::Importer.stub(:new, ->(**kwargs) {
        seen << kwargs[:psub_id]
        raise Aws::S3::Errors::NotFound.new(nil, 'Not Found')
      }) do
        assert_raises(Aws::S3::Errors::NotFound) { DataMigration::SyncBpJob.perform_now(run.id) }
      end
    end

    assert_equal 1, seen.size, 'the second row must never have been attempted'

    run.reload

    assert_equal 0, run.counters.fetch('failed', 0), 'a dead backend is not a row outcome'
    assert_match(/\[PSUB001\] STOPPED/, run.error_log)
    assert_match(/object storage is unreachable/, run.error_log)
    assert_match(/SeaweedFS/, run.error_log)
  end

  test 'already-completed run is a no-op on re-perform (no double-counting)' do
    rows = [make_row('PSUB001', accession: 'PRJDB901')]
    fake = FakeStagingClient.new(rows)

    run = MigrationRun.create!(db: 'bioproject')

    BioProject::StagingClient.stub(:new, fake) do
      DataMigration::SyncBpJob.perform_now(run.id)
    end
    run.reload
    counters_after_first = run.counters.dup
    started_at_after_first = run.started_at

    # Re-perform the same run id (would happen if an operator manually
    # re-enqueues a completed run via console). Without the
    # completed-status guard the perform would re-run the loop from
    # cursor=nil and merge-add a second batch of counters onto the row.
    BioProject::StagingClient.stub(:new, fake) do
      DataMigration::SyncBpJob.perform_now(run.id)
    end
    run.reload

    assert_equal 'completed', run.status
    assert_equal counters_after_first, run.counters, 'completed run must not have counters double-incremented'
    assert_equal started_at_after_first.to_i, run.started_at.to_i, 'completed run must not bump started_at'
  end

  test 'cursor stored verbatim — resume picks up at next id, not skipping the cursor row' do
    # Pin the off-by-one fix at the cursor-persistence layer. The job
    # uses step.set!(source_id) (verbatim) not step.advance!(from:)
    # (which would store source_id.succ and skip one row per interrupt
    # given StagingClient's `WHERE submission_id > $1`).
    rows = [
      make_row('PSUB100', accession: 'PRJDB100'),
      make_row('PSUB200', accession: 'PRJDB200')
    ]
    fake = FakeStagingClient.new(rows)

    # Sanity: the fake client's `after:` semantics match real
    # StagingClient — strict `>`. PSUB100 is excluded; PSUB200 returns.
    assert_equal %w[PSUB200], fake.submission_ids(after: 'PSUB100')
  end
end
