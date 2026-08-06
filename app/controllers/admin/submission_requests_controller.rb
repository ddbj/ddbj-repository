module Admin
  # The request is the single curation unit: the index is the unified
  # workbench list (every request, with its submission's curation state
  # and cross-submission bulk actions) and the show is the one-page
  # detail that embeds the submission workbench underneath the request
  # metadata, validation, and the submitter ↔ curator thread.
  class SubmissionRequestsController < ApplicationController
    include RequestListing
    include SubmissionDetail
    include RequestSearch

    before_action :load_workbench, only: %i[show samples messages record]

    # Ordered by last touched, not by id. On a ledger the question is
    # almost always "what moved", and creation order answers that only for
    # a corpus nobody has come back to — which this is not.
    def index
      scope = SubmissionRequest.order(updated_at: :desc)

      @total = scope.reorder(nil).count

      scope = filter_by_query(scope, params[:q])                       if params[:q].present?
      scope = filter_by_db(scope, params[:db])                         if params[:db].present?
      scope = filter_by_request_status(scope, params[:request_status]) if params[:request_status].present?
      scope = filter_by_status(scope, params[:status])                 if params[:status].present?
      scope = filter_by_assignee(scope, params[:assignee], staff)      if params[:assignee].present?

      # The last press this curator made, until they put it away. The
      # ledger is where the bulk happened, so it is where "what did that
      # actually do" belongs — see accession_issuance_runs/_summary.
      @issuance_run = AccessionIssuanceRun
                      .undismissed_for(current_actor)
                      .includes(issuances: {submission: :request})
                      .first

      @saved_views = current_user.saved_views.ordered.to_a

      # One query for the staff list, which this screen asks about four
      # times over: the assignee facet's own checkboxes, the filter it
      # applies, what "every assignee" means when normalising the URL,
      # and whether a saved view names somebody who has since gone.
      @staff           = staff
      @assignee_ids    = ['0'] + staff.map { it.id.to_s }
      @assignee_labels = SavedView.assignee_labels(@saved_views)

      load_requests(scope)

      redirect_out_of_range_page(@pagy)
    end

    # --- workbench tabs -------------------------------------------------
    # Overview answers "what state is this in and what is the next move",
    # Samples is the bulk-edit workbench, Messages is the conversation and
    # Record & history is the provenance. Each loads only what it renders.

    def show
      @validation = @state.validation
      @activity   = ActivityFeed.new(@request).entries

      load_materialised(@submission) if @submission
    end

    def samples
      return redirect_to admin_submission_request_path(@request) unless @submission&.biosample_db?

      @search = SampleSearch.new(@submission.samples, params)
      scope   = @search.scope

      # `page_key: 'samples_page'` namespaces the URL param. (pagy v43:
      # the option is `page_key`, not `page_param`, and the value must be
      # a String not a Symbol; the wrong shape is silently ignored.)
      @samples_pagy, @samples = pagy(scope.order(:id), page_key: 'samples_page', limit: 50)
      @matching_count         = @samples_pagy.count

      redirect_out_of_range_page(@samples_pagy, key: :samples_page)
    end

    # Opening the tab records nothing. It used to mark the thread read for
    # EVERY curator, so a colleague glancing at it took the request out of
    # the assignee's queue as well as their own — and "somebody looked" is
    # not "I know about this". Replying and Mark as read are what discharge
    # it now, each for the curator who did it.
    def messages
      # The thread renders each message's attachments as well as its
      # author, and `:user` does not cover them — one pair of queries per
      # message otherwise.
      @messages = @request.messages.includes(:user, files_attachments: :blob).to_a
    end

    def record
      load_record_detail(@submission) if @submission
    end

    private

    def load_workbench
      @request    = SubmissionRequest.includes(:user).find(params[:id])
      @submission = @request.submission
      @state      = CurationState.new(@request, viewer: current_user)
    end

    # The submission-based filters (source_id / accession / status)
    # correlate on `submission_requests.submission_id`, which IS the
    # submission's primary key. A request with no submission (pre-Apply)
    # matches none of them, so those filters implicitly restrict to
    # applied requests — exactly the curation cohort. `assignee` is not
    # one of them: it lives on the request and works before Apply.

    # Multi-select filters treat "everything selected" the same as
    # "nothing selected" — a fully-checked group is no constraint. This
    # keeps the default all-checked view showing every request (including
    # pre-Apply ones the submission-based EXISTS filters would otherwise
    # exclude), and lets the "Deselect all" button clear a facet.
    def full_or_empty?(selected, universe_size)
      selected.empty? || selected.size >= universe_size
    end

    def filter_by_db(scope, raw)
      selected = Array(raw).map(&:to_s) & SubmissionRequest.dbs.keys
      return scope if full_or_empty?(selected, SubmissionRequest.dbs.size)

      scope.where('submission_requests.db': selected)
    end

    # Filter on the request's own pipeline status (waiting_validation …
    # applied), OR-ing the multi-selected values. Applies to every request,
    # unlike the submission-based filters. Unknown values are dropped so a
    # stale/typo'd URL param never raises on the enum coercion.
    def filter_by_request_status(scope, raw)
      selected = Array(raw).map(&:to_s) & SubmissionRequest.statuses.keys
      return scope if full_or_empty?(selected, SubmissionRequest.statuses.size)

      scope.where(status: selected)
    end

    # Match iff the applied submission's BP project status OR any of its BS
    # samples' status is one of the requested names (OR across the multi
    # select). Unknown names are dropped; an all-unknown set is a no-op.
    def filter_by_status(scope, raw)
      names = Array(raw).map(&:to_s) & Lifecycleable::STATUSES.keys
      return scope if full_or_empty?(names, Lifecycleable::STATUSES.size)

      sids = names.map { Lifecycleable::STATUSES.fetch(it) }
      scope.where(<<~SQL.squish, sids:)
        EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.status IN (:sids)) OR
        EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.status  IN (:sids))
      SQL
    end

    # `assignee` is a multi select: `0` means "unassigned" and any other
    # value is a user id. Now that assignment is a column on the request
    # this is a plain indexed IN — it used to need an EXISTS over both
    # curation tables, which also meant a pre-Apply request could never
    # match any assignee filter, not even "unassigned".
    # Loaded whole rather than plucked, because the screen needs both the
    # ids (the filter) and the uids (the checkboxes), and ordered because
    # that is how the boxes are listed.
    def staff = @staff ||= User.staff.order(:uid).to_a

    def filter_by_assignee(scope, raw, staff)
      # Universe = "unassigned" (0) + every staff user. Not a static enum,
      # so it is computed rather than looked up — but the rule is the one
      # every other filter follows: intersect first, then treat a full or
      # empty selection as no constraint.
      #
      # Without the intersection this was the one filter that acted on a
      # value the screen had already dropped: `?assignee[]=999999` — which
      # a saved view naming a curator who has since left produces — asked
      # for a user nobody is assigned to and returned an empty ledger
      # under "nothing has ever been here".
      universe = ['0'] + staff.map { it.id.to_s }
      selected = Array(raw).map(&:to_s).reject(&:blank?) & universe

      return scope if selected.empty? || (universe - selected).empty?

      ids = (selected - ['0']).map(&:to_i).reject(&:zero?)
      ids << nil if selected.include?('0')

      scope.where(assignee_id: ids)
    end
  end
end
