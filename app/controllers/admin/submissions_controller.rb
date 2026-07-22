module Admin
  # Submission-scoped actions that hang off a submission id — the raw
  # materialised JSON, the per-submission and cross-submission bulk
  # curation ops, and the accession/edit resources. The list + detail
  # UI lives on SubmissionRequestsController (the request is the unit);
  # a bare submission link redirects there.
  class SubmissionsController < ApplicationController
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
          return redirect_to admin_submission_request_path(submission.request), alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Sample.statuses.fetch(raw[:status])
      end

      if raw.key?(:assignee_id) && raw[:assignee_id] != ''
        if raw[:assignee_id] == '0'
          attrs[:assignee_id] = nil
        else
          assignee = User.find_by(id: raw[:assignee_id])
          unless assignee&.admin?
            return redirect_to admin_submission_request_path(submission.request), alert: 'Assignee must be an admin user.'
          end

          attrs[:assignee_id] = assignee.id
        end
      end

      if attrs.empty?
        return redirect_to admin_submission_request_path(submission.request),
                           alert: 'No changes specified (both fields left as-is).'
      end

      attrs[:updated_at] = Time.current
      affected = submission.samples.update_all(attrs)

      redirect_to admin_submission_request_path(submission.request),
                  notice: "Bulk-updated #{helpers.number_with_delimiter(affected)} sample(s)."
    end

    # Cross-submission bulk: apply (status, assignee) to many submissions
    # in one form post from the index. BP submissions' Project row is
    # updated; BS submissions' Samples rows are all updated. Validation
    # for status / assignee mirrors `bulk_update_samples`.
    def bulk_update
      ids = Array(params.dig(:bulk, :submission_ids)).map(&:to_i).reject(&:zero?).uniq

      if ids.empty?
        return redirect_to admin_submission_requests_path(index_filter_params),
                           alert: 'No submissions selected.'
      end

      raw = bulk_cross_params
      attrs = {}

      if raw[:status].present?
        unless Lifecycleable::STATUSES.key?(raw[:status])
          return redirect_to admin_submission_requests_path(index_filter_params),
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
            return redirect_to admin_submission_requests_path(index_filter_params),
                               alert: 'Assignee must be an admin user.'
          end

          attrs[:assignee_id] = assignee.id
        end
      end

      if attrs.empty?
        return redirect_to admin_submission_requests_path(index_filter_params),
                           alert: 'No changes specified (both fields left as-is).'
      end

      attrs[:updated_at] = Time.current

      subs   = Submission.where(id: ids)
      bp_ids = subs.where(db: 'bioproject').pluck(:id)
      bs_ids = subs.where(db: 'biosample').pluck(:id)

      bp_affected = bp_ids.any? ? Project.where(submission_id: bp_ids).update_all(attrs) : 0
      bs_affected = bs_ids.any? ? Sample.where(submission_id: bs_ids).update_all(attrs) : 0

      redirect_to admin_submission_requests_path(index_filter_params),
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
        return redirect_to admin_submission_requests_path(index_filter_params),
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

      redirect_to admin_submission_requests_path(index_filter_params)
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
