module Admin
  # Submission-scoped actions that hang off a submission id — the raw
  # materialised JSON, the per-submission and cross-submission bulk
  # curation ops, and the accession/edit resources. The list + detail
  # UI lives on SubmissionRequestsController (the request is the unit);
  # a bare submission link redirects there.
  class SubmissionsController < ApplicationController
    include RowTargeting

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
    # RowTargeting). Assignment is not here: it belongs to the request
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
      raw     = bulk_row_params

      return redirect_to back, alert: 'No samples selected.' if empty_selection?

      if raw[:status].present?
        unless Sample.statuses.key?(raw[:status])
          return redirect_to back, alert: "Unknown status: #{raw[:status].inspect}."
        end

        attrs[:status] = Sample.statuses.fetch(raw[:status])
      end

      return redirect_to back, alert: 'No changes specified (status left as-is).' if attrs.empty?

      attrs[:updated_at] = Time.current
      affected = (target_rows(submission) || submission.samples).update_all(attrs)

      record_curation_event(submission, affected, raw)
      participate!(submission.request)

      redirect_to back, notice: "Bulk-updated #{helpers.number_with_delimiter(affected)} sample(s)."
    rescue RowTargeting::UnknownScope => e
      redirect_to admin_submission_request_path(submission.request), alert: "Cannot apply: #{e.message}"
    end

    # The Entries tab's bulk, which is the Samples tab's bulk over a
    # different table. Retracting an entry — canceled or withdrawn — is
    # what keeps it out of the flatfile, so this is the screen that
    # decides what goes out.
    def bulk_update_entries
      submission = Submission.find(params[:id])
      return head :not_found unless submission.st26_db?

      back = submission_return_path(submission)
      raw  = bulk_row_params

      return redirect_to back, alert: 'No entries selected.' if empty_selection?
      return redirect_to back, alert: 'No changes specified (status left as-is).' if raw[:status].blank?

      unless Entry::SETTABLE_STATUSES.include?(raw[:status])
        return redirect_to back, alert: "Unknown status: #{raw[:status].inspect}."
      end

      affected = (target_rows(submission) || submission.entries)
                 .update_all(status: Entry.statuses.fetch(raw[:status]), updated_at: Time.current)

      # Withdrawing entries is what takes them out of what goes out, so it
      # is the last thing that should happen without a name against it.
      record_curation_event(submission, affected, raw)
      participate!(submission.request)

      redirect_to back, notice: "Bulk-updated #{helpers.number_with_delimiter(affected)} entry/entries."
    rescue RowTargeting::UnknownScope => e
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

      subs     = Submission.where(id: ids)
      bp_ids   = subs.where(db: 'bioproject').pluck(:id)
      bs_ids   = subs.where(db: 'biosample').pluck(:id)
      st26_ids = subs.where(db: 'st26').pluck(:id)

      projects = Applied.none
      samples  = Applied.none
      entries  = Applied.none
      assigned = Applied.none

      if attrs.any?
        attrs[:updated_at] = Time.current

        projects = apply_status(Project.where(submission_id: bp_ids), attrs)

        # Entries counted with the samples: both are "the rows of a
        # submission", and the notice names them by the submission's own
        # noun. ST.26 was missing here entirely — the selection reported
        # "no curation rows" and filed an event saying 0 rows changed,
        # while the same status applied fine from the Entries tab.
        samples = apply_status(Sample.where(submission_id: bs_ids), attrs)
        entries = apply_status(Entry.where(submission_id: st26_ids), attrs)
      end

      if assign
        assignee_id = raw[:assignee_id] == '0' ? nil : raw[:assignee_id].to_i
        scope       = SubmissionRequest.where(submission_id: ids)
        already     = scope.where(assignee_id:).count

        matched = scope.update_all(assignee_id:, updated_at: Time.current)
        assigned = Applied.new(changed: matched - already, unchanged: already)
      end

      record_cross_submission_events(subs, bp_ids, bs_ids, raw)
      SubmissionRequest.where(submission_id: ids).find_each { participate!(it) }

      redirect_to bulk_return_path, notice: bulk_notice(projects:, samples:, entries:, assigned:, raw:)
    end

    # The confirmation for the ledger's bulk. Same component the single
    # submission uses; only the content differs.
    def confirm_issue_accessions
      ids = selected_submission_ids

      return redirect_to bulk_return_path, alert: 'No submissions selected.' if ids.empty?

      @plan   = AccessionPlan.for(Submission.where(id: ids).includes(:request, :project).to_a)
      @action = bulk_issue_accessions_admin_submissions_path(index_filter_params)
      @cancel = bulk_return_path
      @ids    = ids

      render 'admin/accessions/new'
    end

    # Cross-submission bulk accession issuance from the ledger: one job
    # per selected submission (BP → 1 PRJDB, BS → all un-accessioned
    # samples).
    #
    # It used to run them here, in series, each holding the Sequence row
    # lock through a chain replay — so a curator who ticked ten BioSample
    # submissions waited for all ten. Each now reports its own outcome on
    # its own AccessionIssuance row, and one refusal cannot stall the
    # rest because they no longer share a request.
    def bulk_issue_accessions
      ids = selected_submission_ids

      if ids.empty?
        return redirect_to bulk_return_path,
                           alert: 'No submissions selected.'
      end

      run = AccessionIssuanceRun.create!(
        actor:      current_actor,
        origin:     "All requests (#{ids.size} #{'submission'.pluralize(ids.size)})",
        started_at: Time.current
      )

      # Every selected submission gets a row, including the ones the
      # confirmation already showed as skipped. The refusal is the job's
      # to make — deciding it here from the preview would mean a
      # submission that became issuable in between is turned away by a
      # stale reading, and the run page would be missing the line that
      # says what happened to it.
      Submission.where(id: ids).find_each do |submission|
        issuance = submission.accession_issuances.create!(
          run:,
          actor:      run.actor,
          started_at: Time.current
        )

        IssueAccessionsJob.perform_later(issuance_id: issuance.id)
      end

      # Participation is recorded by the job, on the ones that actually
      # issued: ticking ten boxes should not subscribe a curator to ten
      # requests, three of which turn out to refuse.
      redirect_to admin_accession_issuance_run_path(run)
    end

    private

    def selected_submission_ids
      Array(params.dig(:bulk, :submission_ids)).map(&:to_i).reject(&:zero?).uniq
    end

    # Status and assignee never reach the DDBJ Record, so `update_all`
    # leaves no patch and no actor behind. The event is what makes a bulk
    # edit answerable later — see CurationEvent.
    def record_curation_event(submission, row_count, raw)
      CurationEvent.record!(
        submission:,
        actor:     current_actor,
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
    # What a bulk write actually did, told apart from what it merely
    # covered. `update_all` reports rows MATCHED, so a row already at the
    # target status counted the same as one that moved — and "Bulk-updated
    # 10 project(s)" is not something a curator can check against what
    # they ticked.
    #
    # A record for this would be heavier than the operation deserves: Apply
    # is reversible and synchronous, and the ledger below the notice
    # already shows the new state. What was missing was only the honest
    # count.
    Applied = Data.define(:changed, :unchanged) do
      def self.none = new(changed: 0, unchanged: 0)

      def any? = changed.positive? || unchanged.positive?
    end

    # Counted before the write, because afterwards the two are
    # indistinguishable. Still writes the whole scope, so `updated_at`
    # moves exactly where it did before.
    def apply_status(scope, attrs)
      already = scope.where(status: attrs[:status]).count
      matched = scope.update_all(attrs)

      Applied.new(changed: matched - already, unchanged: already)
    end

    # Two sentences, each carrying its own pair. Joining them with
    # `to_sentence` produced "Nothing to set and 1 row already curating",
    # which is a list of fragments rather than a statement of what
    # happened.
    def bulk_notice(projects:, samples:, entries:, assigned:, raw:)
      parts = [status_notice(projects, samples, entries, raw), assignee_notice(assigned, raw)].compact

      # A selection with nothing to act on — every request in it applied
      # but not yet carrying rows. An empty string still renders an empty
      # green alert, which is worse than the old vague sentence it
      # replaced.
      return 'Nothing to update — the selection has no curation rows.' if parts.empty?

      parts.join(' ')
    end

    def status_notice(projects, samples, entries, raw)
      return nil unless projects.any? || samples.any? || entries.any?

      status = raw[:status]

      # Named by what each kind of row is called. A mixed selection reads
      # "Set 1 project and 40 entries to public" — "40 rows" would be
      # shorter and would leave the curator to work out which.
      moved = [
        (helpers.pluralize(projects.changed, 'project') if projects.changed.positive?),
        (helpers.pluralize(samples.changed,  'sample')  if samples.changed.positive?),
        (helpers.pluralize(entries.changed,  'entry')   if entries.changed.positive?)
      ].compact

      already = projects.unchanged + samples.unchanged + entries.unchanged
      tail    = " #{helpers.pluralize(already, 'row')} #{already == 1 ? 'was' : 'were'} already #{status}." if already.positive?

      if moved.any?
        "Set #{moved.to_sentence} to #{status}.#{tail}"
      else
        "Nothing to set —#{tail&.chomp('.')}."
      end
    end

    def assignee_notice(assigned, raw)
      return nil unless assigned.any?

      who  = assignee_label(raw[:assignee_id])
      tail = " #{helpers.pluralize(assigned.unchanged, 'request')} already #{who == 'unassigned' ? 'had none' : "had #{who}"}." if assigned.unchanged.positive?

      if assigned.changed.zero?
        "No assignee to change —#{tail&.chomp('.')}."
      elsif who == 'unassigned'
        "Unassigned #{helpers.pluralize(assigned.changed, 'request')}.#{tail}"
      else
        "Assigned #{helpers.pluralize(assigned.changed, 'request')} to #{who}.#{tail}"
      end
    end

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

    def bulk_row_params
      params.expect(bulk_row: [:status, :scope, {ids: []}])
    end

    def bulk_cross_params
      params.expect(bulk: [:status, :assignee_id, {submission_ids: []}])
    end

    # Where a cross-request bulk action lands once it has run: back on the
    # ledger with its filter intact. The filter is rebuilt from the posted
    # params rather than from a client-supplied URL, so there is no
    # redirect target to sanitise.
    def bulk_return_path
      admin_submission_requests_path(index_filter_params)
    end

    # Carry the current index filter selection across a bulk-update
    # redirect so the curator lands back on the same filtered view. Must
    # stay in step with what the ledger's form actually puts in the URL —
    # this listed three params the ledger no longer has and missed `q`,
    # so a curator who searched, ticked rows and pressed Apply came back
    # to the unfiltered list with their search gone.
    def index_filter_params
      params.permit(:q, :page, db: [], request_status: [], status: [], assignee: []).to_h
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
