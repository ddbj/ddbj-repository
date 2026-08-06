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
    admin/migration_runs
    admin/regenerate_flatfiles
    admin/regenerate_flatfiles_runs
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

  # Something in the box, so saving is a press rather than a naming
  # decision — but short. The whole filter summary was the first thing
  # tried and it made the chip a restatement of the badge row two lines
  # below it, in a pill wide enough to push everything else off the line.
  # A name is what the curator will recognise it by; the summary is
  # already on screen.
  def suggested_view_name(params)
    return params[:q].to_s.strip.first(SavedView::MAX_NAME_LENGTH) if params[:q].present?

    key    = REQUEST_FILTER_LABELS.keys.find { Array(params[it]).reject(&:blank?).any? }
    values = Array(params[key]).reject(&:blank?)

    values.first.to_s.tr('_', ' ').capitalize
  end

  # A saved view is grey; the one on screen is filled in; one whose
  # values no longer all exist is amber. Amber doubts, per CLAUDE.md —
  # the view opens, it just shows more than it was saved with, and the
  # current view being stale is still worth colouring as stale.
  def saved_view_button_class(current:, stale:)
    return 'btn-outline-warning' if stale
    return 'btn-primary'         if current

    'btn-outline-secondary'
  end

  # The full name, because the chip truncates, plus what the view has
  # stopped matching. Both are things the pill cannot show and the reader
  # needs on hover.
  def saved_view_title(view, unknown)
    return view.name if unknown.empty?

    "#{view.name} — no longer matches #{unknown.values.flatten.join(', ')}, " \
      'so it now shows more than it was saved with.'
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

  # `elapsed_label` with the preposition it needs: "40s ago", but "just
  # now" rather than "just now ago".
  def elapsed_phrase(time)
    label = elapsed_label(time)

    label.in?(['just now', '—']) ? label : "#{label} ago"
  end

  # Relative time, with the absolute one carried along: `datetime` for
  # anything reading the markup, `title` for whoever hovers. Rounding to
  # "4d" is what makes a queue readable, and it is also what makes it
  # impossible to answer "which Tuesday?" — so the exact value never
  # leaves, it just stops taking up room.
  def elapsed_time(time, label: nil)
    return '—' unless time

    tag.time(label || elapsed_phrase(time), datetime: time.iso8601, title: format_datetime(time))
  end

  # Long enough that a row deserves to be looked at rather than scrolled
  # past. Colour is the only thing separating "moving" from "stalled" once
  # everything in a queue is by definition waiting.
  def stale?(time, threshold: 1.day)
    time.present? && time < threshold.ago
  end

  # "about 3 hours" — the half of "regenerate 7,254 submissions" that
  # decides whether it happens now or tonight. Silent until this
  # installation has finished a run to measure, because the only number
  # worth putting next to a destructive button is one that came from
  # somewhere.
  def regeneration_estimate(count, rate: RegenerateFlatfilesRun.measured_rate)
    return nil if rate.nil? || count.zero?

    distance_of_time_in_words(rate * count)
  end

  # The three ways a list can be empty, which are three different
  # situations for whoever is looking at it. See the conventions in
  # CLAUDE.md.
  #
  #   :first_run — nothing has ever been here; say what will appear, and
  #                offer the way to start. The only one with an action.
  #   :filtered  — rows exist, none match; recite what is on and offer to
  #                clear it.
  #   :clear     — empty is the point, as in a queue; say so as an
  #                outcome and leave nothing to press.
  def empty_state(kind, title, detail = nil, &action)
    tag.div(class: 'text-center text-body-secondary py-4', data: {test_empty_state: kind}) do
      safe_join([
        tag.p(title, class: "mb-1#{' text-body' if kind == :clear}"),
        (tag.p(detail, class: 'small mb-0') if detail.present?),
        (tag.div(capture(&action), class: 'mt-2') if action && kind != :clear)
      ].compact)
    end
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

  # Everything a curator would otherwise be asked for in a support
  # thread, in one paste: which import, which submission, when, and what
  # went wrong. Assembled here rather than in the template so the shape
  # stays one thing.
  def support_details(import)
    [
      "Sample TSV import ##{import.id}",
      # No bare "(#)": a submission from before requests existed has no
      # id to quote, and an empty parenthetical is the one line a support
      # thread would have to ask back about.
      ["Submission: #{import.submission.source_id}",
       ("(##{import.submission.request.id})" if import.submission.request)].compact.join(' '),
      "Uploaded by: #{import.actor}",
      "Finished: #{format_datetime(import.finished_at)}",
      '',
      import.error_report
    ].join("\n")
  end

  # "#1482", linked. A submission imported before requests existed can
  # still be issued against, so the id is not guaranteed to be there —
  # and an em dash beats a broken link.
  def issuance_request_link(issuance)
    request = issuance.submission.request

    request ? link_to("##{request.id}", admin_submission_request_path(request)) : '—'
  end

  # Whether the submitter was told, in one phrase. The run page puts it
  # in a column and the ledger summary in a sentence; what it says is the
  # same in both, and it is read off what was recorded at issuance rather
  # than worked out again here — the environment's mail allowlist is
  # temporary, and a page that re-derived this would start claiming old
  # runs had mailed people the day the restriction is lifted.
  #
  # Only a genuine send failure is red: it is the one that leaves work
  # behind, and per CLAUDE.md red asserts. A recipient the allowlist held
  # back is the environment behaving as configured, and the banner at the
  # top of every admin page has already said so.
  def mail_outcome(issuance)
    case issuance.mail_status
    when 'sent'       then "sent #{format_datetime(issuance.finished_at)}"
    when 'failed'     then tag.span('not sent', class: 'text-danger-emphasis')
    when 'restricted' then 'not delivered (restricted)'
    when 'no_address' then 'no address on file'
    else                   issuance.loading? ? 'after commit' : 'not sent'
    end
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

  # How much of a migration run's work is done, in one phrase: "28,410 of
  # 45,900" while the total is known, the count alone when it is not, and
  # the failures alongside because a run that imported everything and a
  # run that imported everything but three are different results.
  def migration_run_rows(run)
    done   = number_with_delimiter(run.counters_total)
    failed = run.counters['failed'].to_i

    rows = run.total.to_i.positive? ? "#{done} of #{number_with_delimiter(run.total)} rows" : "#{done} rows"

    failed.positive? ? "#{rows} · #{number_with_delimiter(failed)} failed" : rows
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
