module Admin
  # Accession issuance, started from the workbench or the Samples screen.
  #
  # POST /admin/submissions/:submission_id/accession
  #
  # BP: 1 PRJDB, stamped onto the Project row and the record. BS: a SAMD
  # for the targeted samples — every un-accessioned one by default, or the
  # subset the Samples screen picked (see SampleTargeting).
  #
  # The work runs in IssueAccessionsJob rather than here: the Sequence row
  # lock is held until the surrounding transaction commits, and that
  # transaction replays the patch chain and uploads a blob. See the
  # accession_issuances migration.
  class AccessionsController < ApplicationController
    include SampleTargeting

    def show
      @submission = Submission.find(params[:submission_id])
      @issuance   = @submission.accession_issuances.find(params[:id])
    end

    # The confirmation. Same component the ledger's bulk uses — the
    # content shrinks to one submission, the wording and the weight do
    # not. "Only confirm when several are selected" would wave through
    # the workbench's single button, which on a BioSample submission can
    # be tens of thousands of samples.
    def new
      submission = Submission.find(params[:submission_id])

      if empty_selection?
        return redirect_to submission_return_path(submission), alert: 'No samples selected.'
      end

      @plan   = AccessionPlan.for([submission], targeting: targeting_for(submission))
      @action = admin_submission_accessions_path(submission, filter_passthrough)
      @cancel = submission_return_path(submission)

      # The original params, re-emitted verbatim. Recomputing the
      # targeting here and handing it to `create` as a new shape would
      # add a second thing to trust; this way `create` reads exactly what
      # it read before the confirmation existed.
      @passthrough = params.slice(:bulk_sample).permit(bulk_sample: [:scope, {sample_ids: []}]).to_h
    rescue SampleTargeting::UnknownScope => e
      redirect_to submission_return_path(submission), alert: "Cannot issue accession: #{e.message}"
    end

    # Reached by POST from the Samples screen, whose checkbox selection
    # has to travel in a form body. Same action, and it has to say so —
    # an alias would leave Rails looking for a `confirm` template and
    # answering 204.
    def confirm
      new

      render :new unless performed?
    end

    def create
      submission = Submission.find(params[:submission_id])

      if empty_selection?
        return redirect_to submission_return_path(submission), alert: 'No samples selected.'
      end

      run = AccessionIssuanceRun.create!(
        actor:      current_actor,
        origin:     "##{submission.request&.id} (1 submission)",
        started_at: Time.current
      )

      issuance = submission.accession_issuances.create!(
        run:,
        actor:      run.actor,
        targeting:  targeting_for(submission),
        started_at: Time.current
      )

      IssueAccessionsJob.perform_later(issuance_id: issuance.id)

      redirect_to admin_accession_issuance_run_path(run)
    rescue SampleTargeting::UnknownScope => e
      redirect_to submission_return_path(submission), alert: "Cannot issue accession: #{e.message}"
    end

    private

    # The Samples screen's filter travels in the action URL, so it has to
    # be put back on the one the confirmation posts to.
    def filter_passthrough
      params.permit(:q, :accession, status: []).to_h.compact_blank
    end

    # What the curator asked for, in the form they expressed it. A
    # filtered scope is stored as its filter and re-derived when the job
    # runs, so the button still means "every row matching this" rather
    # than a snapshot of ids the browser never saw.
    def targeting_for(submission)
      return {} unless submission.biosample_db?

      case params.dig(:bulk_sample, :scope).presence
      when nil        then {}
      when 'selected' then {scope: 'selected', sample_ids: selected_sample_ids}
      when 'filtered' then {scope: 'filtered', filter: SampleSearch.new(submission.samples, params).to_params}
      else                 raise SampleTargeting::UnknownScope, "Unknown target: #{params.dig(:bulk_sample, :scope).inspect}."
      end
    end
  end
end
