module Admin
  # The request is the single curation unit: the index is the unified
  # workbench list (every request, with its submission's curation state
  # and cross-submission bulk actions) and the show is the one-page
  # detail that embeds the submission workbench underneath the request
  # metadata, validation, and the submitter ↔ curator thread.
  class SubmissionRequestsController < ApplicationController
    include SubmissionDetail
    include SourceIdFilterable

    def index
      scope = SubmissionRequest
        .includes(:user, submission: [{project: :assignee}, :accessions])
        .order(id: :desc)

      scope = filter_by_db(scope, params[:db])                         if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user]))        if params[:user].present?
      scope = filter_by_request_status(scope, params[:request_status]) if params[:request_status].present?
      scope = filter_by_source_id(scope, params[:source_id])           if params[:source_id].present?
      scope = filter_by_accession(scope, params[:accession])           if params[:accession].present?
      scope = filter_by_status(scope, params[:status])                 if params[:status].present?
      scope = filter_by_assignee(scope, params[:assignee])             if params[:assignee].present?

      @pagy, @requests   = pagy(scope)
      @sample_aggregates = sample_aggregates_for(@requests.filter_map(&:submission))
    end

    def show
      @request    = SubmissionRequest.includes(:user).find(params[:id])
      @submission = @request.submission
      @validation = @request.validation_with_validity
      @messages   = @request.messages.includes(:user).to_a

      # Mark unread submitter messages as read by virtue of any curator
      # opening this page — keeps the "返信待ち" indicator semantically
      # "any curator has looked".
      @request.messages.submitter_role.unread.update_all(read_at: Time.current)

      load_submission_detail(@submission) if @submission
    end

    private

    # The submission-based filters (source_id / accession / status /
    # assignee) correlate on `submission_requests.submission_id`, which
    # IS the submission's primary key. A request with no submission
    # (pre-Apply) matches none of them, so those filters implicitly
    # restrict to applied requests — exactly the curation cohort.

    # Per-BS-submission aggregate of (status, assignee) across samples,
    # so the index can show "Uniform: public / kodama" vs "Mixed (3)"
    # without hauling every Sample row over the wire. One SQL for the
    # whole page — no N+1, no per-row distinct() calls.
    SampleAggregate = Data.define(:statuses, :assignee_ids, :first_accession, :accession_count)

    def sample_aggregates_for(submissions)
      bs_ids = submissions.select(&:biosample_db?).map(&:id)
      return {} if bs_ids.empty?

      rows = Sample
        .where(submission_id: bs_ids)
        .group(:submission_id)
        .pluck(:submission_id,
               Arel.sql('ARRAY_AGG(DISTINCT status) AS statuses'),
               Arel.sql('ARRAY_AGG(DISTINCT assignee_id) AS assignee_ids'),
               Arel.sql('MIN(accession) AS first_accession'),
               Arel.sql('COUNT(accession) AS accession_count'))

      rows.to_h {|sid, statuses, assignees, first_accession, accession_count|
        [sid, SampleAggregate.new(statuses:, assignee_ids: assignees, first_accession:, accession_count:)]
      }
    end

    # Longer than any real PSUB/SSUB/PRJDB/SAMD/SAMN/etc. accession. Bounds
    # both the SQL ILIKE cost and the request-log payload for crafted/fuzzed
    # input.
    MAX_FILTER_LENGTH = 64

    def normalize_filter_value(raw)
      return '' unless raw.is_a?(String)

      raw.strip[0, MAX_FILTER_LENGTH] || ''
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

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

    # Case-insensitive PREFIX match OR-ed across the three accession-bearing
    # associations (projects for BP, samples for BS, accessions for ST26).
    def filter_by_accession(scope, raw)
      value = normalize_filter_value(raw)
      return scope if value.empty?

      scope.where(<<~SQL.squish, pattern: "#{sanitize_sql_like(value)}%")
        EXISTS (SELECT 1 FROM projects   WHERE projects.submission_id   = submission_requests.submission_id AND projects.accession   ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM samples    WHERE samples.submission_id    = submission_requests.submission_id AND samples.accession    ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM accessions WHERE accessions.submission_id = submission_requests.submission_id AND accessions.number    ILIKE :pattern)
      SQL
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

    # `assignee` is a multi select: `0` means "unassigned" (assignee_id IS
    # NULL on a project/sample row) and any other value is a user id. The
    # selected values are OR-ed — a row matches if it is assigned to ANY of
    # the picked users, or unassigned when "0" is picked.
    def filter_by_assignee(scope, raw)
      selected = Array(raw).map(&:to_s).reject(&:blank?)
      return scope if selected.empty?

      # Universe = "unassigned" (0) + every staff user. Selecting all of it
      # is no constraint (see full_or_empty? — same rule, computed here
      # because the universe needs a query).
      universe = ['0'] + User.staff.pluck(:id).map(&:to_s)
      return scope if (universe - selected).empty?

      include_unassigned = selected.include?('0')
      uids               = (selected - ['0']).map(&:to_i).reject(&:zero?)

      predicates = []
      predicates << 'assignee_id IN (:uids)' if uids.any?
      predicates << 'assignee_id IS NULL'    if include_unassigned
      return scope if predicates.empty?

      # `predicate` is built only from the two fixed literals above; the
      # user-supplied ids ride in via the :uids bind, so there's no
      # interpolation of untrusted input.
      predicate = predicates.join(' OR ')
      scope.where(<<~SQL.squish, uids:)
        EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND (#{predicate})) OR
        EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND (#{predicate}))
      SQL
    end
  end
end
