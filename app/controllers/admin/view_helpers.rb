module Admin::ViewHelpers
  DB_LABELS = {
    'st26'       => 'ST.26',
    'bioproject' => 'BioProject',
    'biosample'  => 'BioSample'
  }.freeze

  STATUS_COLORS = {
    'waiting_validation'  => 'secondary',
    'validating'          => 'warning',
    'validation_failed'   => 'danger',
    'ready_to_apply'      => 'success',
    'waiting_application' => 'secondary',
    'applying'            => 'warning',
    'applied'             => 'primary',
    'application_failed'  => 'danger',
    'no_change'           => 'light'
  }.freeze

  FLASH_CLASSES = {
    'notice' => 'success',
    'alert'  => 'danger',
    'error'  => 'danger'
  }.freeze

  MIGRATION_RUN_STATUS_COLORS = {
    'queued'    => 'secondary',
    'running'   => 'warning',
    'completed' => 'success',
    'failed'    => 'danger'
  }.freeze

  def db_label(db)
    DB_LABELS.fetch(db.to_s, db.to_s)
  end

  # Primary curator-facing identifier for a submission. Uses the staging
  # source_id (PSUB.../SSUB...) when present so admin pages match how
  # curators talk about records; falls back to the internal
  # "Submission-#{id}" form for ST.26 (no source_id, since it comes from
  # user uploads rather than D-way migration).
  def submission_label(submission)
    submission.source_id.presence || "Submission-#{submission.id}"
  end

  def db_options
    DB_LABELS.map {|value, label| [label, value] }
  end

  def status_badge(status)
    color = STATUS_COLORS.fetch(status.to_s, 'secondary')

    tag.span status.to_s.tr('_', ' '), class: "badge text-bg-#{color} text-capitalize"
  end

  def flash_bootstrap_class(level)
    FLASH_CLASSES.fetch(level.to_s, 'secondary')
  end

  def migration_run_status_badge(run)
    color = MIGRATION_RUN_STATUS_COLORS.fetch(run.status, 'secondary')

    tag.span run.status, class: "badge text-bg-#{color} text-capitalize"
  end
end
