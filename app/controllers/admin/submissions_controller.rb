module Admin
  class SubmissionsController < ApplicationController
    def index
      # Project away `cached_materialised_record` (bytea, BS-scale ~7MB
      # per row) — the index view never reads it, and pagy(20) × 7MB =
      # 140MB transferred per page once caches are warmed.
      #
      # Preload project + assignee for the per-row BP status/assignee
      # columns. BS shows aggregated per-sample status/assignee instead
      # (computed below in one SQL).
      scope = Submission
        .select(Submission.column_names - %w[cached_materialised_record])
        .includes(:user, project: :assignee)
        .order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?
      scope = filter_by_source_id(scope, params[:source_id]) if params[:source_id].present?
      scope = filter_by_accession(scope, params[:accession]) if params[:accession].present?
      scope = filter_by_status(scope, params[:status])       if params[:status].present?
      scope = filter_by_assignee(scope, params[:assignee])   if params[:assignee].present?

      @pagy, @submissions = pagy(scope)
      @sample_aggregates  = sample_aggregates_for(@submissions)
    end

    # Canonicalisation walks every subtree and produces canonical bytes +
    # SHA-256 for each, which costs ~20s on a 7 MB record (BS 20K-sample
    # scale, see SSUB004153). Skip both display rows above this size and
    # surface a banner instead — the curator can still pull the raw
    # materialised JSON via the dedicated `materialised` action below.
    CANONICAL_DISPLAY_SIZE_LIMIT = 1.megabyte

    def show
      @submission = Submission.includes(:user).find(params[:id])
      @updates    = @submission.updates.order(:id).to_a

      # Samples list is paginated inside a turbo-frame so 20K-row BS
      # records don't blow up the page. `page_key: 'samples_page'`
      # namespaces the URL param so future paginators on the same page
      # won't collide. (pagy v43: option name is `page_key` not
      # `page_param`, and the value must be a String not a Symbol; the
      # wrong shape is silently ignored.)
      if @submission.biosample_db?
        # `includes(:assignee)` preloads the assignee for the 20-row page
        # so the table's Assignee column doesn't N+1.
        @samples_pagy, @samples = pagy(@submission.samples.includes(:assignee).order(:id),
                                       page_key: 'samples_page', limit: 20)

        # For the Accession row in the dl. One extra COUNT vs walking
        # samples is cheaper than reading the bytea-projected materialised.
        @accessioned_sample_count = @submission.samples.where.not(accession: nil).count
      end

      begin
        @materialised = @submission.materialised_record

        if @materialised
          # `@materialised_size` is the Oj :strict serialised byte length,
          # cached in an ivar so the view's size badge does not re-encode.
          # NOTE this is the JSON dump size, NOT the canonical byte count;
          # the dl above shows `@canonical_bytes.bytesize` (post-JCS) which
          # is structurally different and usually a bit smaller.
          @materialised_size = Oj.dump(@materialised, mode: :strict).bytesize

          if @materialised_size <= CANONICAL_DISPLAY_SIZE_LIMIT
            @canonical_bytes = DDBJRecord::Canonicalizer.canonicalize(@materialised)
            # Hash the already-computed canonical bytes instead of calling
            # Canonicalizer.sha256, which re-canonicalises from scratch.
            @sha256 = Digest::SHA256.hexdigest(@canonical_bytes)
          end
        end
      rescue Submission::MaterialisationFailed, DDBJRecord::Canonicalizer::Error => e
        @materialisation_error = e
      end
    end

    # Raw materialised v3 JSON for the submission.
    #
    # - No `?as_of` (or as_of that parse_as_of rejects: blank, non-numeric,
    #   non-positive) — returns the latest snapshot. Cache-aware: when the
    #   bytea cache is populated, ships those bytes directly without an
    #   Oj.load / re-encode roundtrip.
    # - `?as_of=N` where N matches a SubmissionUpdate on this submission —
    #   returns the snapshot at that update. ALWAYS replays through
    #   materialise_at, even when N happens to equal latest_id; the cache
    #   shortcut would race with a concurrent append landing between the
    #   id check and the read, serving a newer state under a URL pinned to
    #   a specific id.
    # - `?as_of=N` where N is positive but unknown on this submission —
    #   404 (stale link explicitly rejected; we do not silently fall back
    #   to latest because the curator asked for a specific snapshot).
    # - MaterialisationFailed during replay — 422 with the offending
    #   update_id in the JSON body. Sibling `show` surfaces the same
    #   condition as the "Replay failed" banner.
    def materialised
      submission = Submission.find(params[:id])
      requested  = parse_as_of(params[:as_of])

      payload =
        if requested
          update = submission.updates.find_by(id: requested)
          return head :not_found unless update

          Oj.dump(submission.materialise_at(update_id: update.id), mode: :strict)
        else
          cached = submission.cached_materialised_record

          if cached.present?
            cached
          else
            record = submission.materialised_record
            return head :not_found unless record

            Oj.dump(record, mode: :strict)
          end
        end

      render plain: payload, content_type: 'application/json'
    rescue Submission::MaterialisationFailed => e
      render json:   {error: 'replay_failed', update_id: e.update_id, message: e.message},
             status: :unprocessable_entity
    end

    # Bulk-apply (status, assignee) to every Sample in a BS submission.
    # Uses `update_all` (1 SQL) so the 20K-sample case stays interactive,
    # which bypasses ActiveRecord validations + callbacks — we validate
    # both fields manually upfront.
    #
    # Empty form field = "leave as-is" (key omitted from the update);
    # `assignee_id = "0"` is the explicit "set to unassigned" sentinel
    # (distinguishable from leave-as-is because '' parses as blank).
    def bulk_update_samples
      submission = Submission.find(params[:id])
      return head :not_found unless submission.biosample_db?

      attrs   = {}
      raw     = bulk_sample_params

      if raw[:status].present?
        unless Sample.statuses.key?(raw[:status])
          return redirect_to admin_submission_path(submission), alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Sample.statuses.fetch(raw[:status])
      end

      if raw.key?(:assignee_id) && raw[:assignee_id] != ''
        if raw[:assignee_id] == '0'
          attrs[:assignee_id] = nil
        else
          assignee = User.find_by(id: raw[:assignee_id])
          unless assignee&.admin?
            return redirect_to admin_submission_path(submission), alert: 'Assignee must be an admin user.'
          end

          attrs[:assignee_id] = assignee.id
        end
      end

      if attrs.empty?
        return redirect_to admin_submission_path(submission),
                           alert: 'No changes specified (both fields left as-is).'
      end

      attrs[:updated_at] = Time.current
      affected = submission.samples.update_all(attrs)

      redirect_to admin_submission_path(submission),
                  notice: "Bulk-updated #{helpers.number_with_delimiter(affected)} sample(s)."
    end

    # Cross-submission bulk: apply (status, assignee) to many submissions
    # in one form post from the index. BP submissions' Project row is
    # updated; BS submissions' Samples rows are all updated. Validation
    # for status / assignee mirrors `bulk_update_samples`.
    def bulk_update
      ids = Array(params.dig(:bulk, :submission_ids)).map(&:to_i).reject(&:zero?).uniq

      if ids.empty?
        return redirect_to admin_submissions_path(index_filter_params),
                           alert: 'No submissions selected.'
      end

      raw = bulk_cross_params
      attrs = {}

      if raw[:status].present?
        unless Lifecycleable::STATUSES.key?(raw[:status])
          return redirect_to admin_submissions_path(index_filter_params),
                             alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Lifecycleable::STATUSES.fetch(raw[:status])
      end

      if raw.key?(:assignee_id) && raw[:assignee_id] != ''
        if raw[:assignee_id] == '0'
          attrs[:assignee_id] = nil
        else
          assignee = User.find_by(id: raw[:assignee_id])
          unless assignee&.admin?
            return redirect_to admin_submissions_path(index_filter_params),
                               alert: 'Assignee must be an admin user.'
          end

          attrs[:assignee_id] = assignee.id
        end
      end

      if attrs.empty?
        return redirect_to admin_submissions_path(index_filter_params),
                           alert: 'No changes specified (both fields left as-is).'
      end

      attrs[:updated_at] = Time.current

      subs   = Submission.where(id: ids)
      bp_ids = subs.where(db: 'bioproject').pluck(:id)
      bs_ids = subs.where(db: 'biosample').pluck(:id)

      bp_affected = bp_ids.any? ? Project.where(submission_id: bp_ids).update_all(attrs) : 0
      bs_affected = bs_ids.any? ? Sample.where(submission_id: bs_ids).update_all(attrs) : 0

      redirect_to admin_submissions_path(index_filter_params),
                  notice: "Bulk-updated #{helpers.number_with_delimiter(bp_affected)} project(s) " \
                          "+ #{helpers.number_with_delimiter(bs_affected)} sample(s) " \
                          "across #{ids.size} submission(s)."
    end

    # Cross-submission bulk accession issuance from the index. Walks each
    # selected submission through `AccessionIssue` (BP → 1 PRJDB, BS →
    # all un-accessioned samples). Refused submissions surface in the
    # flash with their reason; successful ones are summarised. The
    # per-submission service handles transactions + mail enqueue, so
    # one failure doesn't poison the rest.
    def bulk_issue_accessions
      ids = Array(params.dig(:bulk, :submission_ids)).map(&:to_i).reject(&:zero?).uniq

      if ids.empty?
        return redirect_to admin_submissions_path(index_filter_params),
                           alert: 'No submissions selected.'
      end

      issued = 0
      refused = []

      Submission.where(id: ids).find_each do |submission|
        result = AccessionIssue.call(submission:, actor: "admin:#{current_user.uid}")
        issued += result.accessions.size
      rescue AccessionIssue::Refused => e
        refused << [submission.source_id.presence || "##{submission.id}", e.message]
      end

      notice = "Issued #{helpers.number_with_delimiter(issued)} accession(s) across #{ids.size - refused.size} submission(s)."
      notice += " #{refused.size} refused." if refused.any?

      flash[:notice] = notice
      flash[:alert]  = refused.map {|sid, msg| "#{sid}: #{msg}" }.join("\n") if refused.any?

      redirect_to admin_submissions_path(index_filter_params)
    end

    private

    def bulk_sample_params
      params.expect(bulk_sample: %i[status assignee_id])
    end

    def bulk_cross_params
      params.expect(bulk: [:status, :assignee_id, {submission_ids: []}])
    end

    # Carry the current index filter selection across a bulk-update
    # redirect so the curator lands back on the same filtered view.
    def index_filter_params
      params.slice(:db, :user, :source_id, :accession, :status, :assignee).permit!.to_h
    end

    # Per-BS-submission aggregate of (status, assignee) across samples,
    # so the index can show "Uniform: public / kodama" vs "Mixed (3)"
    # without hauling every Sample row over the wire. One SQL for the
    # whole page — no N+1, no per-row distinct() calls.
    #
    # Returns a Hash keyed by submission_id, with keys :statuses /
    # :assignee_ids (Arrays of distinct integer values; nil assignee
    # surfaces as nil in the array).
    SampleAggregate = Data.define(:statuses, :assignee_ids)

    def sample_aggregates_for(submissions)
      bs_ids = submissions.select(&:biosample_db?).map(&:id)
      return {} if bs_ids.empty?

      rows = Sample
        .where(submission_id: bs_ids)
        .group(:submission_id)
        .pluck(:submission_id,
               Arel.sql('ARRAY_AGG(DISTINCT status) AS statuses'),
               Arel.sql('ARRAY_AGG(DISTINCT assignee_id) AS assignee_ids'))

      rows.to_h {|sid, statuses, assignees| [sid, SampleAggregate.new(statuses:, assignee_ids: assignees)] }
    end

    # Strict positive-integer parser. Returns nil for anything other than
    # an explicit positive integer; callers treat nil as "no cutoff" /
    # "use latest".
    def parse_as_of(raw)
      return nil if raw.blank?

      parsed = Integer(raw, 10, exception: false)
      parsed&.positive? ? parsed : nil
    end

    # Longer than any real PSUB/SSUB/PRJDB/SAMD/SAMN/etc. accession. Bounds
    # both the SQL ILIKE cost and the request-log payload for crafted/fuzzed
    # input.
    MAX_FILTER_LENGTH = 64

    # Coerce param input to a bounded, trimmed string. Non-String shapes
    # (Array, Hash, ActionController::Parameters) become '' so the calling
    # helpers no-op on them instead of raising NoMethodError on sanitize.
    def normalize_filter_value(raw)
      return '' unless raw.is_a?(String)

      raw.strip[0, MAX_FILTER_LENGTH] || ''
    end

    # Case-insensitive PREFIX match on submissions.source_id. Column name is
    # table-qualified so a future scope chain that joins a sibling table
    # with a same-named column does not trip Postgres ambiguous-column.
    def filter_by_source_id(scope, raw)
      value = normalize_filter_value(raw)
      return scope if value.empty?

      scope.where('submissions.source_id ILIKE ?', "#{sanitize_sql_like(value)}%")
    end

    # Case-insensitive PREFIX match OR-ed across the three accession-bearing
    # associations (projects for BP, samples for BS, accessions for ST26).
    # EXISTS subqueries avoid the row duplication a join would introduce
    # when a single submission has many matching samples / entries.
    def filter_by_accession(scope, raw)
      value = normalize_filter_value(raw)
      return scope if value.empty?

      pattern = "#{sanitize_sql_like(value)}%"
      scope.where(<<~SQL.squish, pattern:)
        EXISTS (SELECT 1 FROM projects   WHERE projects.submission_id   = submissions.id AND projects.accession   ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM samples    WHERE samples.submission_id    = submissions.id AND samples.accession    ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM accessions WHERE accessions.submission_id = submissions.id AND accessions.number    ILIKE :pattern)
      SQL
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

    # Match a submission iff its BP project status OR any of its BS
    # samples' status equals the requested name. ST26 has no
    # status_id of this shape so its rows are filtered out by the
    # OR-of-EXISTS construction. Unknown status names are a no-op
    # (defensive — keeps a typo in the URL from breaking the page).
    def filter_by_status(scope, raw)
      value = raw.to_s.strip
      return scope unless Lifecycleable::STATUSES.key?(value)

      sid = Lifecycleable::STATUSES.fetch(value)
      scope.where(<<~SQL.squish, sid:)
        EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submissions.id AND projects.status = :sid) OR
        EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submissions.id AND samples.status  = :sid)
      SQL
    end

    # `assignee=0` means "unassigned" (i.e. assignee_id IS NULL on at
    # least one project/sample row). A user id matches when any
    # project/sample row is assigned to that user.
    def filter_by_assignee(scope, raw)
      value = raw.to_s.strip
      return scope if value.empty?

      if value == '0'
        scope.where(<<~SQL.squish)
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submissions.id AND projects.assignee_id IS NULL) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submissions.id AND samples.assignee_id  IS NULL)
        SQL
      else
        uid = value.to_i
        scope.where(<<~SQL.squish, uid:)
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submissions.id AND projects.assignee_id = :uid) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submissions.id AND samples.assignee_id  = :uid)
        SQL
      end
    end
  end
end
