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
  # zero total on a *running* run means it is still counting. A queued
  # one has not been picked up at all, and saying it is counting would
  # assert work that has not begun — which is exactly what a backed-up
  # or stopped queue looks like.
  def enumerating? = total.to_i.zero? && running_status?

  def remaining = [total.to_i - counters_total, 0].max

  # Counters as [key, sentence, count], in OUTCOMES order, keeping any
  # key the job has learned since this list was written rather than
  # dropping it silently.
  def outcome_rows
    known   = OUTCOMES.filter_map {|key, label| [key, label, counters[key].to_i] if counters.key?(key) }
    unknown = (counters.keys - OUTCOMES.keys).sort.map { [it, it.humanize, counters[it].to_i] }

    known + unknown
  end

  # The log is one entry per row that did not import — `[PSUB000318]
  # Some::Error: message` — which answers "which row" and never "what do
  # I fix". Grouping on the cause turns twenty entries into the two or
  # three things they are.
  #
  # An entry is a header line plus everything after it that is not
  # itself a header: `error.message` goes into the log verbatim, and
  # Postgres messages carry their DETAIL on the next line. Splitting on
  # newlines put those continuations in with the run-level notices,
  # where a sweep with fifteen thousand failures would have rendered
  # fifteen thousand warning paragraphs.
  ROW_ENTRY   = /\A\[([^\]]+)\]\s*(.+)\z/
  RUN_ENTRY   = /\A(ABANDONED:|TERMINAL )/
  SAMPLES     = 3

  # Rows the run could not import, grouped by cause, most common first.
  #
  # Not only the ones counted `failed`: a row refused for belonging to
  # another submitter is counted `cross_user`, and one that stopped the
  # sweep is not counted at all. All of them are rows that did not
  # import, which is what the screen says.
  def unimported_groups
    entries = log_entries.select { it[:source_id] }

    entries.group_by { normalise_cause(it[:cause]) }.map {|_, matched|
      # Shown with the first message of the group rather than the
      # normalised key: the key exists to collapse the identifiers, and
      # reading "Missing organism in X" back to a curator would be worse
      # than the log it replaced.
      {cause:      matched.first[:cause].truncate(160),
       count:      matched.size,
       source_ids: matched.first(SAMPLES).map { it[:source_id] },
       truncated:  matched.size > SAMPLES}
    }.sort_by { -it[:count] }
  end

  # The full text of those entries, continuations included — the whole
  # thing being summarised above, for reading offline.
  def unimported_text = log_entries.select { it[:source_id] }.map { it[:text] }.join("\n")

  # Entries about the run rather than about a row: why it was abandoned,
  # or what stopped it. Matched on the prefixes the job actually writes,
  # so a stray line cannot become one.
  def notices = log_entries.reject { it[:source_id] }.map { it[:text] }

  # Read off the raw string rather than through `log_entries`: the index
  # asks every row for this, and most rows have nothing to say.
  def abandoned_reason = error_log.to_s[/^ABANDONED:\s*(.+)$/, 1]

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

  # The log, split into entries. A header line starts one; anything else
  # continues the entry above it. A line before any header — there
  # should not be one — is kept as its own entry rather than dropped.
  def log_entries
    @log_entries ||= error_log.to_s.lines.each_with_object([]) {|line, entries|
      stripped = line.rstrip

      next if stripped.blank?

      if (row = ROW_ENTRY.match(stripped))
        entries << {source_id: row[1], cause: row[2], text: stripped}
      elsif RUN_ENTRY.match?(stripped) || entries.empty?
        entries << {source_id: nil, cause: stripped, text: stripped}
      else
        entries.last[:text] += "\n#{stripped}"
      end
    }
  end

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
