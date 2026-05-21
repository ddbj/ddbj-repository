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

  def db_label(db)
    DB_LABELS.fetch(db.to_s, db.to_s)
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
end
