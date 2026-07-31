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

  # One workbench tab per question: what state is this in / what needs
  # bulk editing / what is being discussed / where did the record come
  # from. Ordered as rendered.
  WORKBENCH_TABS = {
    overview: 'Overview',
    samples:  'Samples',
    messages: 'Messages',
    record:   'Record & history'
  }.freeze

  # Curation status is the nine-state Lifecycleable enum. Colour by what
  # the state means for the curator: amber = in hand, green = done and
  # out, grey/dark = parked or terminated.
  CURATION_STATUS_COLORS = {
    'submission_accepted'    => 'secondary',
    'curating'               => 'warning',
    'accession_issued'       => 'info',
    'private'                => 'secondary',
    'public'                 => 'success',
    'withdrawn'              => 'danger',
    'canceled'               => 'danger',
    'permanently_suppressed' => 'dark',
    'temporarily_suppressed' => 'dark'
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

  # Everything reachable from the nav's Tools dropdown. Listed here so the
  # dropdown lights up while the curator is inside one of them, the same
  # way a top-level nav item does.
  TOOLS_CONTROLLERS = %w[
    admin/users
    admin/distribution_notices
    admin/distribution_notice_templates
    admin/regenerate_flatfiles
  ].freeze

  # The facets a ledger view actually has on, summarised so the row stays
  # one line: a multi-select reads as "Curation: Curating +1" rather than
  # spelling out every checked value.
  REQUEST_FILTER_LABELS = {db: 'Database', request_status: 'Pipeline', status: 'Curation', assignee: 'Assignee'}.freeze

  def active_request_filters(params)
    REQUEST_FILTER_LABELS.filter_map {|key, label|
      values = Array(params[key]).reject(&:blank?)
      next if values.empty?

      "#{label}: #{values.first.to_s.tr('_', ' ').capitalize}#{" +#{values.size - 1}" if values.size > 1}"
    }
  end

  def request_filters_active?(params)
    REQUEST_FILTER_LABELS.keys.any? { Array(params[it]).reject(&:blank?).any? }
  end

  # Compact elapsed time for a queue: "9h", "4d". The question a queue
  # answers is "has this been sitting?", which minute precision only
  # obscures — and the row is sorted by it anyway.
  def elapsed_label(time)
    return '—' unless time

    seconds = Time.current - time

    case seconds
    when ...60         then 'just now'
    when ...1.hour     then "#{(seconds / 60).to_i}m"
    when ...1.day      then "#{(seconds / 1.hour).to_i}h"
    else                    "#{(seconds / 1.day).to_i}d"
    end
  end

  # Long enough that a row deserves to be looked at rather than scrolled
  # past. Colour is the only thing separating "moving" from "stalled" once
  # everything in a queue is by definition waiting.
  def stale?(time, threshold: 1.day)
    time.present? && time < threshold.ago
  end

  def workbench_tab_label(tab)
    WORKBENCH_TABS.fetch(tab)
  end

  # DDBJ Account's account type, in words plus the code it is stored
  # under — the name is what a curator reads, the number is what they
  # quote when they take the question to DDBJ Account. An unknown value is
  # shown as it arrived rather than swallowed.
  def account_type_label(raw)
    name = CloakmanClient.account_type_name(raw)
    return '—' if name.blank?

    label  = CloakmanClient::ACCOUNT_TYPE_LABELS.fetch(name, name.humanize)
    number = CloakmanClient::ACCOUNT_TYPES.key(name)

    number ? "#{label} (type #{number})" : label
  end

  def admin_tools_section?
    controller_path.in?(TOOLS_CONTROLLERS) || controller_path.start_with?('mission_control/')
  end

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

  # Curation status of a whole request. A BS submission's samples can
  # disagree, in which case there is no one colour to show — "Mixed (3)"
  # reads as neutral rather than as a state.
  def curation_status_badge(state)
    status = state.uniform_status
    color  = status ? CURATION_STATUS_COLORS.fetch(status, 'secondary') : 'light border'

    tag.span state.status_label, class: "badge text-bg-#{color} text-capitalize"
  end

  # The migration run that produced a migrated request, so the Overview
  # can link to it instead of explaining an empty File field with
  # "(migration-sourced)". Returns nil for interactively-submitted
  # requests and for runs whose row has since been deleted.
  def migration_run_for(request, submission)
    uuid = request.migration_run_id || submission&.migration_run_id
    return nil if uuid.blank?

    MigrationRun.find_by(uuid:)
  end

  def flash_bootstrap_class(level)
    FLASH_CLASSES.fetch(level.to_s, 'secondary')
  end

  def migration_run_status_badge(run)
    color = MIGRATION_RUN_STATUS_COLORS.fetch(run.status, 'secondary')

    tag.span run.status, class: "badge text-bg-#{color} text-capitalize"
  end

  # The ledger's one state column. A request's meaningful state changes
  # hands at Apply: before it the pipeline status IS the state, after it
  # the curation status is. ST.26 is never curated through this UI, so it
  # keeps showing the pipeline status for its whole life — which is why
  # this falls back rather than printing a dash.
  def request_state_display(request, submission, sample_aggregates)
    curation = submission && submission_status_display(submission, sample_aggregates)

    curation || status_badge(request.status)
  end

  # Curation status of a Submission, or nil when it has none.
  #   - BP: the Project's Lifecycleable status.
  #   - BS: aggregate over Samples — "<status>" if uniform, "Mixed (N)" if not.
  #   - ST26: nil (not curated through this UI).
  def submission_status_display(submission, sample_aggregates)
    if submission.bioproject_db?
      submission.project&.status&.tr('_', ' ')
    elsif submission.biosample_db?
      agg = sample_aggregates[submission.id]
      return nil unless agg

      if agg.statuses.size == 1
        # `Sample.statuses` is {'public' => 5500, ...} so invert is keyed by integer.
        Sample.statuses.invert.fetch(agg.statuses.first, agg.statuses.first.to_s).tr('_', ' ')
      else
        "Mixed (#{agg.statuses.size})"
      end
    end
  end

  # Accession display for a Submission on the admin index — returns
  # [first_accession, count]. The DB-specific branching lives on
  # Submission#accession_summary; here we just hand it the BS aggregate
  # ([first, count]) pulled from the page's one grouped sample query.
  def accession_summary(submission, sample_aggregates)
    agg = sample_aggregates[submission.id]
    submission.accession_summary(agg && [agg.first_accession, agg.accession_count])
  end
end
