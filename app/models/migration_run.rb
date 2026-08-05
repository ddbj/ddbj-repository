# Lifecycle row for a single D-way → ddbj-repository batch import run.
#
# Owned by DataMigration::SyncJob (and its BP/BS subclasses). The job
# resumes via ActiveJob::Continuation, so `status` / cursor / counters
# are written by a single worker per `db`. That single-writer property
# is enforced at the call site: the admin controller and rake task
# refuse to enqueue when a run for the same `db` is already queued or
# running (limits_concurrency is deliberately avoided — it would
# discard a Continuable retry; see DataMigration::SyncJob).
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

  # How long a run with no progress is still believed to be running.
  #
  # The job writes counters every CHECKPOINT_EVERY rows, so `updated_at`
  # moves every few minutes even on BioSample, where a single 7 MB record
  # costs seconds to canonicalise. An hour of silence is a worker that is
  # gone — and without a bound, one such row blocks every future import
  # of that database with no way out of the UI.
  STALE_AFTER = 1.hour

  # What the enqueue precheck honours: a run that is still moving, or
  # recent enough that it might be.
  scope :in_flight, -> { where(status: %w[queued running], updated_at: STALE_AFTER.ago..) }

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
  # writer per (db) thanks to the enqueue-time precheck (see the class
  # comment), so a reload + merge + save is race-free.
  def merge_counters!(increments)
    return if increments.empty?

    reload
    merged = counters.dup
    increments.each {|outcome, n| merged[outcome.to_s] = merged.fetch(outcome.to_s, 0) + n }
    update!(counters: merged)
  end

  # Queued or running, and no longer moving. A curator may abandon one of
  # these; a run that is still progressing they may not, because a second
  # worker on the same database would then write over the first.
  def stale? = (queued_status? || running_status?) && updated_at < STALE_AFTER.ago

  # Give up on a run whose worker is gone, and say so in the log rather
  # than leaving a `failed` with no reason in it.
  def abandon!(reason)
    update!(status: :failed, finished_at: Time.current)
    append_error!("ABANDONED: #{reason}")
  end

  def append_error!(message)
    reload
    update!(error_log: [error_log, message].compact_blank.join("\n"))
  end
end
