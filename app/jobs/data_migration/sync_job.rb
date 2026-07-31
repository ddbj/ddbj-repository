module DataMigration
  # Base class for the per-DB (BP / BS) D-way → ddbj-repository sync jobs.
  #
  # Resumable via ActiveJob::Continuation. The only step is :sync; the
  # cheap setup (find run, mark running, open client, fetch total) runs
  # outside any step so a network blip during enumeration just fails the
  # current perform — the next perform starts fresh from line 1. The
  # long part (per-row import loop) lives inside `step :sync` so SIGTERM
  # / deploy / Continuable-retryable errors resume from the persisted
  # cursor without re-processing imported rows.
  #
  # Cursor persistence: `step.set!(source_id)` writes the source_id
  # VERBATIM (not source_id.succ). This matches StagingClient's strict
  # `WHERE submission_id > $1` — on resume the next call returns rows
  # strictly greater than the last successfully-processed id. Using
  # `step.advance!(from: id)` here would store `id.succ` and silently
  # skip exactly one row per interrupt.
  #
  # Counter persistence: increments accumulate in-memory and flush to
  # the MigrationRun row every CHECKPOINT_EVERY rows. The inner
  # `begin/ensure` around the per-row loop guarantees a final flush on
  # ANY exit path — normal completion, ActiveJob::Continuation::Interrupt
  # (an Exception, not a StandardError), or any other raise. Without
  # the ensure, up to CHECKPOINT_EVERY-1 outcomes per interrupt would
  # be permanently lost (cursor advances per row, counters don't).
  #
  # Status transitions:
  #   queued   → running       (top of perform)
  #   running  → running       (Continuation retry: perform re-runs; no flip)
  #   running  → completed     (success)
  #   running  → failed        (TERMINAL: rescue_from below; either
  #                            ResumeLimitError or a non-advanced
  #                            StandardError that Continuable did not retry)
  #
  # Concurrency: limits_concurrency is intentionally NOT used. Continuable
  # retries via `retry_job(wait: 5.seconds)`, and `limits_concurrency
  # to: 1, on_conflict: :discard` would destroy the retry when the
  # original is still finishing — losing the resume entirely. Instead
  # the admin controller + rake task precheck `MigrationRun.where(db:,
  # status: %w[queued running]).exists?` to prevent duplicate enqueues
  # at the call site.
  class SyncJob < ApplicationJob
    include ActiveJob::Continuable

    CHECKPOINT_EVERY = 100

    queue_as :default

    # Bad migration_run_id (deleted by an operator after enqueue, or
    # mismatched type from a bug) should be discarded silently rather
    # than mark a phantom run :failed.
    discard_on ActiveRecord::RecordNotFound

    # Terminal failure path. Continuable's `continue` rescue catches
    # StandardError and decides retry vs. re-raise; everything that
    # re-raises (ResumeLimitError, non-advanced errors, etc.) lands
    # here. We mark the run :failed AFTER Continuable has given up,
    # so the next perform never overwrites it back to :running.
    rescue_from StandardError do |error|
      @run&.update!(status: :failed, finished_at: Time.current)
      @run&.append_error!("TERMINAL #{error.class}: #{error.message}")
      raise
    end

    def perform(migration_run_id)
      @run = MigrationRun.find(migration_run_id)
      return if @run.completed_status?

      @run.update!(status: :running, started_at: @run.started_at || Time.current, finished_at: nil)
      @client = staging_client_class.new

      @run.update!(total: @client.submission_ids.size) if @run.total.nil?

      Rails.logger.info("[migration_run:#{@run.id}] starting #{@run.db} sync " \
                        "(total=#{@run.total}, uuid=#{@run.uuid})")

      step :sync do |step|
        increments = Hash.new(0)

        begin
          @client.submission_ids(after: step.cursor).each_with_index do |source_id, idx|
            outcome = process_row(source_id)
            increments[outcome] += 1

            # `set!` persists source_id VERBATIM. Do NOT use
            # `advance!(from: source_id)` — it stores source_id.succ
            # and skips one row per interrupt (StagingClient's
            # `WHERE submission_id > $1` is strict).
            step.set!(source_id)

            if ((idx + 1) % CHECKPOINT_EVERY).zero?
              @run.merge_counters!(increments)
              log_progress(source_id)
              increments.clear
            end
          end
        ensure
          # Flushes on EVERY exit — normal end-of-loop, Continuation::Interrupt
          # (Exception subclass), connection error, anything. Without
          # this, outcomes accumulated since the last 100-row flush are
          # silently dropped because the cursor already advanced past
          # those rows.
          @run.merge_counters!(increments)
        end
      end

      # Reconcile total with what we actually saw — D-way is live during
      # 並走運用 so the staging set can grow / shrink during the sweep.
      @run.update!(status: :completed, finished_at: Time.current, total: @run.counters_total)

      Rails.logger.info("[migration_run:#{@run.id}] done. " +
                        @run.counters.map {|k, v| "#{k}=#{v}" }.join(' '))
    ensure
      # `rescue nil` on close — a dead libpq connection's close can raise,
      # and we don't want a teardown error to mask the real cause of failure.
      begin
        @client&.close
      rescue StandardError
        nil
      end
    end

    private

    # Connection-level failures abort the current perform — every
    # subsequent row would fail too. Continuable retries from the
    # cursor; if the resume_limit is hit the rescue_from above marks
    # the run :failed.
    #
    # STORAGE_ERRORS below are the same shape of problem for a different
    # backend, and are re-raised the same way. They are kept separate
    # only because a Postgres failure may be the primary connection, and
    # writing to the run to say so would fail in turn.
    CONNECTION_ERRORS = [
      PG::ConnectionBad,
      PG::UnableToSend,
      ActiveRecord::ConnectionNotEstablished
    ].freeze

    # What an unreachable object store looks like from in here. When
    # kamal-proxy has no container to route to it answers 404 for
    # everything, and ActiveStorage surfaces that as NotFound — the same
    # error a genuinely missing blob raises. Reading it the obvious way
    # ("the blob is gone") is what cost two weeks in June 2026, so the
    # log says which reading to try first.
    #
    # StorageHealthcheckJob is what should catch this before an importer
    # does; this is for the run that started anyway.
    STORAGE_ERRORS = [
      Aws::S3::Errors::NotFound,
      Aws::S3::Errors::NoSuchBucket,
      Seahorse::Client::NetworkingError
    ].freeze

    # Returns the outcome symbol (:created / :updated / :skipped /
    # :no_accession / :no_xml / :no_samples / :missing / :cross_user
    # / :failed). A bad row is absorbed so it does not halt the sweep; a
    # bad backend is not, because there is no sweep left to halt.
    def process_row(source_id)
      run_importer(source_id)
    rescue *CONNECTION_ERRORS
      raise
    rescue *STORAGE_ERRORS => e
      # A backend failure, not a row failure: every row after this one
      # fails the same way. A June 2026 sweep absorbed 15,657 of these
      # one at a time and ran to the end to reach a conclusion the first
      # row already had — leaving an error log too long to read and a
      # corpus of rows marked failed that were never actually looked at.
      #
      # Re-raised like a connection failure, so Continuable retries from
      # the cursor: a store that comes back within the retry window
      # resumes where it stopped, and one that does not marks the run
      # failed. Logged first, because the run has to say where it got to.
      @run.append_error!("[#{source_id}] STOPPED — #{describe_failure(e)}")

      raise
    rescue StandardError => e
      @run.append_error!("[#{source_id}] #{describe_failure(e)}")
      :failed
    end

    def describe_failure(error)
      message = "#{error.class}: #{error.message}"

      return message unless STORAGE_ERRORS.any? { error.is_a?(it) }

      "#{message} — this usually means object storage is unreachable rather than that " \
        'a blob is missing. Check the SeaweedFS accessory before the record.'
    end

    def staging_client_class
      raise NotImplementedError
    end

    def run_importer(_source_id)
      raise NotImplementedError
    end

    def log_progress(last_source_id)
      Rails.logger.info("[migration_run:#{@run.id}] #{@run.counters_total}/#{@run.total} " \
                        "last=#{last_source_id} " +
                        @run.counters.map {|k, v| "#{k}=#{v}" }.join(' '))
    end
  end
end
