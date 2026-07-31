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

    def create
      submission = Submission.find(params[:submission_id])

      if empty_selection?
        return redirect_to submission_return_path(submission), alert: 'No samples selected.'
      end

      issuance = submission.accession_issuances.create!(
        actor:      "admin:#{current_user.uid}",
        targeting:  targeting_for(submission),
        started_at: Time.current
      )

      IssueAccessionsJob.perform_later(issuance_id: issuance.id)

      redirect_to admin_submission_accession_path(submission, issuance),
                  notice: 'Issuing accessions. This page updates itself.'
    rescue SampleTargeting::UnknownScope => e
      redirect_to submission_return_path(submission), alert: "Cannot issue accession: #{e.message}"
    end

    private

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
