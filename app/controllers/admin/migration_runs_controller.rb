module Admin
  class MigrationRunsController < ApplicationController
    JOB_CLASSES = {
      'bioproject' => DataMigration::SyncBpJob,
      'biosample'  => DataMigration::SyncBsJob
    }.freeze

    # Reading past runs stays available everywhere — the history of what
    # was imported is worth having wherever it happened. Starting one is
    # refused where the import is switched off, so a curator is told
    # rather than left watching a job fail.
    before_action :ensure_enabled, only: %i[new create]

    def index
      scope = MigrationRun.recent
      scope = scope.where(db: params[:db]) if params[:db].present?

      @pagy, @migration_runs = pagy(scope)
    end

    def show
      @migration_run = MigrationRun.find(params[:id])

      # Pivot: rows touched by this run. Project away the bytea cache
      # (same rationale as the Submissions index).
      @touched_count = Submission.where(migration_run_id: @migration_run.uuid).count
    end

    def new
      @migration_run = MigrationRun.new(db: params[:db].presence || 'bioproject')
    end

    def create
      db = params.dig(:migration_run, :db)

      job_class = JOB_CLASSES[db.to_s] or
        return redirect_to(new_admin_migration_run_path, alert: "Unknown db: #{db.inspect}")

      # Precheck: refuse to enqueue if there is already a run for this db
      # in flight. Without this, the second click creates a second
      # MigrationRun row whose job races (or with limits_concurrency would
      # be silently discarded), leaving an orphan row stuck at :queued
      # with no way to recover from the UI.
      #
      # `in_flight` rather than the raw statuses: a run whose worker died
      # keeps its status for ever, and the precheck then blocks every
      # future import of that database — the same dead end it was written
      # to avoid, reached from the other side. Superseded runs are closed
      # out rather than ignored, so the list does not go on claiming they
      # are running.
      supersede_stale(db)

      if (existing = MigrationRun.in_flight.where(db: db).order(:id).last)
        return redirect_to admin_migration_run_path(existing),
                           alert: "A #{db} migration run is already #{existing.status} (##{existing.id})."
      end

      run = MigrationRun.create!(db: db)
      job_class.perform_later(run.id)

      redirect_to admin_migration_run_path(run),
                  notice: "Enqueued #{job_class.name} for migration run ##{run.id}."
    end

    # Give up on a run whose worker is gone, from the screen rather than
    # from a console. Only offered once it has stopped moving: abandoning
    # a run that is still progressing would put a second worker on the
    # same database, and the two would write over each other.
    def abandon
      run = MigrationRun.find(params[:id])

      unless run.stale?
        return redirect_to admin_migration_run_path(run),
                           alert: 'This run is still progressing. Abandon is only for one that has stopped.'
      end

      run.abandon!("abandoned by #{current_actor}")

      redirect_to admin_migration_run_path(run), notice: "Migration run ##{run.id} abandoned."
    end

    private

    def ensure_enabled
      return if DataMigration::DwayDefaults.enabled?

      redirect_to admin_migration_runs_path,
                  alert: "Importing from D-way is switched off in #{Rails.env}."
    end

    def supersede_stale(db)
      MigrationRun.where(db: db, status: %w[queued running]).find_each do |run|
        run.abandon!('no progress for over an hour — superseded by a new run') if run.stale?
      end
    end
  end
end
