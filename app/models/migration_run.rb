# Lifecycle row for a single D-way → ddbj-repository batch import run.
#
# Owned by DataMigration::SyncJob (and its BP/BS subclasses). The job
# resumes via ActiveJob::Continuation, so `status` / cursor / counters
# are written by a single concurrent worker per `db` (enforced by
# `limits_concurrency` on the job class) and don't need their own
# concurrency story.
#
# `uuid` is the value passed to BioProject::Importer / BioSample::Importer
# as `migration_run_id:`, so the admin show can pivot to the touched
# Submissions via `Submission.where(migration_run_id: uuid)`.
class MigrationRun < ApplicationRecord
  DBS = %w[bioproject biosample].freeze

  enum :status, {
    queued:    'queued',
    running:   'running',
    completed: 'completed',
    failed:    'failed'
  }, suffix: true, validate: true

  validates :db, presence: true, inclusion: {in: DBS}

  before_validation { self.uuid ||= SecureRandom.uuid }

  scope :recent, -> { order(created_at: :desc) }

  # Sum of every counter bucket (the Importer's :created/:updated/:skipped/
  # :no_accession/etc.). This is what's progressed against `total`.
  def counters_total
    counters.values.sum(&:to_i)
  end

  def progress_percent
    return 0 if total.to_i.zero?

    [(counters_total * 100.0 / total).round, 100].min
  end

  # Apply a batch of in-memory increments collected by the job. Single
  # writer per (db) thanks to limits_concurrency, so a reload + merge +
  # save is race-free.
  def merge_counters!(increments)
    return if increments.empty?

    reload
    merged = counters.dup
    increments.each {|outcome, n| merged[outcome.to_s] = merged.fetch(outcome.to_s, 0) + n }
    update!(counters: merged)
  end

  def append_error!(message)
    reload
    update!(error_log: [error_log, message].compact_blank.join("\n"))
  end
end
