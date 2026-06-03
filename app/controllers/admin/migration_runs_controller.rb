module Admin
  class MigrationRunsController < ApplicationController
    JOB_CLASSES = {
      'bioproject' => DataMigration::SyncBpJob,
      'biosample'  => DataMigration::SyncBsJob
    }.freeze

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

      # Precheck: refuse to enqueue if there is already a queued or running
      # run for this db. Without this, the second click creates a second
      # MigrationRun row whose job races (or with limits_concurrency would
      # be silently discarded), leaving an orphan row stuck at :queued
      # with no way to recover from the UI.
      if (existing = MigrationRun.where(db: db, status: %w[queued running]).order(:id).last)
        return redirect_to admin_migration_run_path(existing),
                           alert: "A #{db} migration run is already #{existing.status} (##{existing.id})."
      end

      run = MigrationRun.create!(db: db)
      job_class.perform_later(run.id)

      redirect_to admin_migration_run_path(run),
                  notice: "Enqueued #{job_class.name} for migration run ##{run.id}."
    end
  end
end
