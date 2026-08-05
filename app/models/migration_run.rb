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

  # What each counter key means, said once, in a fixed order.
  #
  # The keys are the job's vocabulary and reading them takes knowing the
  # importer. Ordered created → updated → skipped → the reasons a row
  # produced nothing → failed, so the same run reads the same way twice
  # — sorting by count put the interesting line somewhere new each time.
  OUTCOMES = {
    'created'      => 'Imported as a new submission',
    'updated'      => 'Updated an existing submission',
    'skipped'      => 'Already identical, nothing written',
    'no_accession' => 'No accession in the source row',
    'no_xml'       => 'No XML in the source row',
    'no_samples'   => 'No samples in the source row',
    'missing'      => 'Not found in the source database',
    'cross_user'   => 'Belongs to a different submitter than the existing record',
    'failed'       => 'Could not be converted'
  }.freeze

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

  # The job counts the source rows before it starts sweeping them, so a
  # zero total on a live run means it is still counting rather than that
  # there is nothing to do.
  def enumerating? = total.to_i.zero? && (queued_status? || running_status?)

  def remaining = [total.to_i - counters_total, 0].max

  # Seconds of work left at the rate this run has managed. Its own rate,
  # measured from its own start — BioSample rows cost seconds each and
  # BioProject rows milliseconds, so nothing carries across.
  def eta
    return nil unless running_status? && counters_total.positive? && remaining.positive?

    (updated_at - started_at) / counters_total * remaining
  end

  # Counters as [key, sentence, count], in OUTCOMES order, keeping any
  # key the job has learned since this list was written rather than
  # dropping it silently.
  def outcome_rows
    known   = OUTCOMES.filter_map {|key, label| [key, label, counters[key].to_i] if counters.key?(key) }
    unknown = (counters.keys - OUTCOMES.keys).sort.map { [it, it.humanize, counters[it].to_i] }

    known + unknown
  end

  # Row failures grouped by what went wrong, most common first.
  #
  # The log is one line per row — `[PSUB000318] Some::Error: message` —
  # which answers "which row" and never "what do I fix". Grouping on the
  # cause turns twenty lines into the two or three things they are.
  ROW_FAILURE = /\A\[([^\]]+)\]\s*(.+)\z/
  SAMPLES     = 3

  def failure_groups
    rows = error_log.to_s.lines.filter_map { ROW_FAILURE.match(it.strip) }

    rows.group_by { normalise_cause(it[2]) }.map {|_, matched|
      # Shown with the first message of the group rather than the
      # normalised key: the key exists to collapse the identifiers, and
      # reading "Missing organism in X" back to a curator would be worse
      # than the log it replaced.
      {cause:      matched.first[2].truncate(160),
       count:      matched.size,
       source_ids: matched.first(SAMPLES).map { it[1] },
       truncated:  matched.size > SAMPLES}
    }.sort_by { -it[:count] }
  end

  # Lines that are about the run rather than about a row: why it was
  # abandoned, or what stopped it.
  def notices = error_log.to_s.lines.map(&:strip).reject { ROW_FAILURE.match?(it) }.compact_blank

  def abandoned_reason = notices.find { it.start_with?('ABANDONED:') }&.delete_prefix('ABANDONED:')&.strip

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

  # The state of one database: what is happening to it now, or what
  # happened last. The screen is organised around this because the rule
  # is — one run per database — and a list of runs makes the reader
  # reconstruct it.
  def self.state_of(db)
    scope = where(db:)

    {db:,
     current: scope.where(status: %w[queued running]).recent.first,
     last:    scope.where(status: %w[completed failed]).recent.first}
  end

  private

  # Two rows that failed the same way differ in the identifiers their
  # messages happen to quote. Grouping on the raw text would put each in
  # its own group of one, which is the log again with extra steps.
  def normalise_cause(message)
    message
      .gsub(/\b[A-Z]{4}\d{4,}\b/, 'X')          # PSUB000318 / SAMD00412919
      .gsub(/\b\d[\d.]*\b/, 'N')                 # ids, counts, byte offsets
      .gsub(/\s+/, ' ')
      .strip
      .truncate(160)
  end
end
