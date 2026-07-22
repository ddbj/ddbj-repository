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

  # Compact timestamp for admin tables / detail — minute precision (drops
  # seconds), matching the web client's formatDatetime. Returns nil for a
  # nil time so callers can chain `|| '—'`.
  def format_datetime(time)
    time&.strftime('%Y-%m-%d %H:%M')
  end

  def db_options
    DB_LABELS.map {|value, label| [label, value] }
  end

  # Inline checkbox group for a multi-select list filter. Emits `name[]`
  # fields so the controller receives an array. `options` is a list of
  # [label, value] pairs; `param_value` is the current request param.
  #
  # When the param is absent (a fresh visit, or a reset) every box is
  # checked — the default is "all selected", which the controller reads
  # as no constraint. Once the form is submitted the checked set is
  # exactly what the user left ticked.
  def filter_checkbox_group(name, options, param_value)
    default_all = param_value.nil?
    chosen      = Array(param_value).map(&:to_s)

    safe_join(options.map {|label, value|
      id = "#{name}_#{value}"

      tag.div(class: 'form-check form-check-inline') do
        check_box_tag("#{name}[]", value, default_all || chosen.include?(value.to_s), id:, class: 'form-check-input') +
          label_tag(id, label, class: 'form-check-label')
      end
    })
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

  # Status display for a Submission on the admin index.
  #   - BP: the Project's Lifecycleable status, or "—" if absent.
  #   - BS: aggregate over Samples — "—" / "<status>" if uniform / "Mixed (N)" if not.
  #   - ST26: "—" (not yet curated through this UI).
  def submission_status_display(submission, sample_aggregates)
    if submission.bioproject_db?
      submission.project&.status&.tr('_', ' ') || '—'
    elsif submission.biosample_db?
      agg = sample_aggregates[submission.id]
      return '—' unless agg

      if agg.statuses.size == 1
        # `Sample.statuses` is {'public' => 5500, ...} so invert is keyed by integer.
        Sample.statuses.invert.fetch(agg.statuses.first, agg.statuses.first.to_s).tr('_', ' ')
      else
        "Mixed (#{agg.statuses.size})"
      end
    else
      '—'
    end
  end

  # Accession display for a Submission on the admin index — returns
  # [first_accession, count], reading the right source per DB: BP → its
  # Project, BS → the sample aggregate (MIN / COUNT), ST.26 → the
  # accessions table. Count 0 means "not issued".
  def accession_summary(submission, sample_aggregates)
    if submission.bioproject_db?
      accession = submission.project&.accession
      [accession, accession ? 1 : 0]
    elsif submission.biosample_db?
      agg = sample_aggregates[submission.id]
      [agg&.first_accession, agg&.accession_count || 0]
    else
      accessions = submission.accessions.to_a
      [accessions.min_by(&:id)&.number, accessions.size]
    end
  end

  # Assignee display for a Submission on the admin index.
  #   - BP: project.assignee.uid, or "—" if unassigned/no project.
  #   - BS: aggregate over Samples — "—" if all unassigned / a single uid if uniform / "Mixed (N)".
  #   - ST26: "—".
  def submission_assignee_display(submission, sample_aggregates)
    if submission.bioproject_db?
      submission.project&.assignee&.uid || '—'
    elsif submission.biosample_db?
      agg = sample_aggregates[submission.id]
      return '—' unless agg
      return '—' if agg.assignee_ids == [nil] || agg.assignee_ids.empty?
      return User.find_by(id: agg.assignee_ids.first)&.uid || '—' if agg.assignee_ids.size == 1

      "Mixed (#{agg.assignee_ids.size})"
    else
      '—'
    end
  end
end
