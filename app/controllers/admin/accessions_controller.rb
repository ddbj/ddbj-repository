module Admin
  # Per-submission accession issuance.
  #
  # POST /admin/submissions/:submission_id/accession
  #
  # BP: issues 1 PRJDB and stamps the Project row + materialised record.
  # BS: issues SAMD accessions for the targeted samples — every
  # un-accessioned one by default, or the subset the Samples screen picked
  # (see SampleTargeting) — and stamps each Sample row + the record.
  #
  # All work lives in `AccessionIssue` so the cross-submission bulk
  # action on the request list can call the same code path.
  class AccessionsController < ApplicationController
    include SampleTargeting

    def create
      submission = Submission.find(params[:submission_id])

      if empty_selection?
        return redirect_to submission_return_path(submission), alert: 'No samples selected.'
      end

      result = AccessionIssue.call(
        submission:,
        actor:   "admin:#{current_user.uid}",
        samples: target_samples(submission)
      )

      first = result.accessions.first
      rest  = result.accessions.size - 1
      label = rest.zero? ? first : "#{first} (+#{rest} more)"

      redirect_to submission_return_path(submission), notice: "Issued accession #{label}."
    rescue AccessionIssue::Refused => e
      redirect_to submission_return_path(submission), alert: "Cannot issue accession: #{e.message}"
    end
  end
end
