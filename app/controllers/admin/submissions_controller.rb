module Admin
  # Submission-scoped actions that hang off a submission id — the raw
  # materialised JSON, the per-submission and cross-submission bulk
  # curation ops, and the accession/edit resources. The list + detail
  # UI lives on SubmissionRequestsController (the request is the unit);
  # a bare submission link redirects there.
  class SubmissionsController < ApplicationController
    include SampleTargeting

    # The submission detail is now rendered inside the request-keyed show
    # (admin/submission_requests#show), so the request stays the single
    # unit. A direct submission link redirects there. Every submission
    # carries a request — real for the interactive flow, synthetic for
    # migration-sourced BP/BS (see Submission#ensure_migration_request!).
    def show
      redirect_to admin_submission_request_path(Submission.find(params[:id]).request)
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
          cached = submission.cached_materialised_bytes

          if cached
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

    # Bulk-apply status to the samples the Samples screen targeted — the
    # checkboxed rows, or every row matching the current filter (see
    # SampleTargeting). Assignment is not here: it belongs to the request
    # as a whole, so there is nothing to apply per sample.
    #
    # Uses `update_all` (1 SQL) so the 100K-sample case stays interactive,
    # which bypasses ActiveRecord validations + callbacks — we validate
    # the status manually upfront.
    #
    # Empty form field = "leave as-is" (key omitted from the update).
    def bulk_update_samples
      submission = Submission.find(params[:id])
      return head :not_found unless submission.biosample_db?

      back    = submission_return_path(submission)
      attrs   = {}
      raw     = bulk_sample_params

      return redirect_to back, alert: 'No samples selected.' if empty_selection?

      if raw[:status].present?
        unless Sample.statuses.key?(raw[:status])
          return redirect_to back, alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Sample.statuses.fetch(raw[:status])
      end

      return redirect_to back, alert: 'No changes specified (status left as-is).' if attrs.empty?

      attrs[:updated_at] = Time.current
      affected = (target_samples(submission) || submission.samples).update_all(attrs)

      record_curation_event(submission, affected, raw)
      participate!(submission.request)

      redirect_to back, notice: "Bulk-updated #{helpers.number_with_delimiter(affected)} sample(s)."
    rescue SampleTargeting::UnknownScope => e
      redirect_to admin_submission_request_path(submission.request), alert: "Cannot apply: #{e.message}"
    end

    # Cross-submission bulk: apply (status, assignee) to many submissions
    # in one form post from the index. The two land in different places —
    # status on the curation rows (the BP Project, every BS Sample),
    # assignee on the request — so they are written separately.
    def bulk_update
      ids = Array(params.dig(:bulk, :submission_ids)).map(&:to_i).reject(&:zero?).uniq

      if ids.empty?
        return redirect_to bulk_return_path,
                           alert: 'No submissions selected.'
      end

      raw   = bulk_cross_params
      attrs = {}

      if raw[:status].present?
        unless Lifecycleable::STATUSES.key?(raw[:status])
          return redirect_to bulk_return_path,
                             alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Lifecycleable::STATUSES.fetch(raw[:status])
      end

      assign = raw.key?(:assignee_id) && raw[:assignee_id] != ''

      if assign && raw[:assignee_id] != '0'
        unless User.find_by(id: raw[:assignee_id])&.admin?
          return redirect_to bulk_return_path, alert: 'Assignee must be an admin user.'
        end
      end

      if attrs.empty? && !assign
        return redirect_to bulk_return_path,
                           alert: 'No changes specified (both fields left as-is).'
      end

      subs   = Submission.where(id: ids)
      bp_ids = subs.where(db: 'bioproject').pluck(:id)
      bs_ids = subs.where(db: 'biosample').pluck(:id)

      bp_affected = 0
      bs_affected = 0

      if attrs.any?
        attrs[:updated_at] = Time.current

        bp_affected = bp_ids.any? ? Project.where(submission_id: bp_ids).update_all(attrs) : 0
        bs_affected = bs_ids.any? ? Sample.where(submission_id: bs_ids).update_all(attrs) : 0
      end

      if assign
        assignee_id = raw[:assignee_id] == '0' ? nil : raw[:assignee_id].to_i

        SubmissionRequest.where(submission_id: ids).update_all(assignee_id:, updated_at: Time.current)
      end

      record_cross_submission_events(subs, bp_ids, bs_ids, raw)
      SubmissionRequest.where(submission_id: ids).find_each { participate!(it) }

      rows = [
        ("#{helpers.number_with_delimiter(bp_affected)} project(s)" if bp_affected.positive?),
        ("#{helpers.number_with_delimiter(bs_affected)} sample(s)"  if bs_affected.positive?)
      ].compact

      summary = rows.any? ? "Bulk-updated #{rows.join(' + ')} across" : 'Updated'

      redirect_to bulk_return_path, notice: "#{summary} #{ids.size} submission(s)."
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
        return redirect_to bulk_return_path,
                           alert: 'No submissions selected.'
      end

      issued = 0
      refused = []

      Submission.where(id: ids).find_each do |submission|
        result = AccessionIssue.call(submission:, actor: "admin:#{current_user.uid}")
        issued += result.accessions.size

        participate!(submission.request)
      rescue AccessionIssue::Refused => e
        refused << [submission.source_id.presence || "##{submission.id}", e.message]
      end

      notice = "Issued #{helpers.number_with_delimiter(issued)} accession(s) across #{ids.size - refused.size} submission(s)."
      notice += " #{refused.size} refused." if refused.any?

      flash[:notice] = notice
      flash[:alert]  = refused.map {|sid, msg| "#{sid}: #{msg}" }.join("\n") if refused.any?

      redirect_to bulk_return_path
    end

    private

    # Status and assignee never reach the DDBJ Record, so `update_all`
    # leaves no patch and no actor behind. The event is what makes a bulk
    # edit answerable later — see CurationEvent.
    def record_curation_event(submission, row_count, raw)
      CurationEvent.record!(
        submission:,
        actor:     "admin:#{current_user.uid}",
        action:    :curation_updated,
        row_count:,
        noun:      submission.curation_row_noun,
        status:    raw[:status].presence,
        assignee:  assignee_label(raw[:assignee_id])
      )
    end

    # One event per submission rather than one for the batch: the activity
    # feed is read per request, and "1,842 samples" has to be that
    # submission's count, not the batch total.
    def record_cross_submission_events(submissions, bp_ids, bs_ids, raw)
      counts = Project.where(submission_id: bp_ids).group(:submission_id).count
                      .merge(Sample.where(submission_id: bs_ids).group(:submission_id).count)

      submissions.each do |submission|
        # An assignee-only batch touches no rows, so it still deserves an
        # event — `count` then reports 0 rather than skipping the record.
        record_curation_event(submission, raw[:status].present? ? counts[submission.id].to_i : 0, raw)
      end
    end

    def assignee_label(raw)
      return nil if raw.blank?
      return 'unassigned' if raw == '0'

      User.find_by(id: raw)&.uid
    end

    def bulk_sample_params
      params.expect(bulk_sample: [:status, :scope, {sample_ids: []}])
    end

    def bulk_cross_params
      params.expect(bulk: [:status, :assignee_id, :return_to, {submission_ids: []}])
    end

    # Where a cross-request bulk action lands once it has run. The shared
    # request list posts a fixed `return_to` key — never a URL — so the
    # curator comes back to the queue they acted from with its filter or
    # bucket selection intact, and there is no redirect target to sanitise
    # beyond this whitelist.
    def bulk_return_path
      case params.dig(:bulk, :return_to)
      when 'needs_action' then admin_root_path(params.permit(:mine).to_h)
      when 'my_queue'     then admin_my_queue_path
      else                     admin_submission_requests_path(index_filter_params)
      end
    end

    # Carry the current index filter selection across a bulk-update
    # redirect so the curator lands back on the same filtered view.
    def index_filter_params
      params.slice(:db, :user, :request_status, :source_id, :accession, :status, :assignee).permit!.to_h
    end

    # Strict positive-integer parser. Returns nil for anything other than
    # an explicit positive integer; callers treat nil as "no cutoff" /
    # "use latest".
    def parse_as_of(raw)
      return nil if raw.blank?

      parsed = Integer(raw, 10, exception: false)
      parsed&.positive? ? parsed : nil
    end
  end
end
