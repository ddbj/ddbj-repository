module Admin
  # Per-submission accession issuance.
  #
  # POST /admin/submissions/:submission_id/accession
  #
  # BP: issues 1 PRJDB and stamps the Project row + materialised record.
  # BS: issues SAMD accessions for every un-accessioned sample in the
  # submission AND stamps each Sample row + materialised record.
  #
  # All work lives in `AccessionIssue` so the cross-submission bulk
  # action on the index can call the same code path.
  class AccessionsController < ApplicationController
    def create
      submission = Submission.find(params[:submission_id])

      result = AccessionIssue.call(submission:, actor: "admin:#{current_user.uid}")

      first = result.accessions.first
      rest  = result.accessions.size - 1
      label = rest.zero? ? first : "#{first} (+#{rest} more)"

      redirect_to admin_submission_path(submission),
                  notice: "Issued accession #{label}."
    rescue AccessionIssue::Refused => e
      redirect_to admin_submission_path(submission),
                  alert: "Cannot issue accession: #{e.message}"
    end
  end
end
