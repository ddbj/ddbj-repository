module Admin
  # One press of Issue and everything it covered.
  #
  # Issuance is one transaction per submission, so this can report "2 of
  # 3 done" honestly — and a failure on the third is visibly confined to
  # the third. It is also where the outcome stays: a flash cannot answer
  # "what number did this get, and when were they told" a week later.
  class AccessionIssuanceRunsController < ApplicationController
    def show
      @run = AccessionIssuanceRun.find(params[:id])

      @issuances = @run.issuances
                       .includes(submission: %i[request project])
                       .order(:id)
    end

    # Puts the ledger's summary away. Scoped to the curator's own runs:
    # the summary is "what the thing I just did did", so dismissing it is
    # not something to be able to do to somebody else's.
    def dismiss
      run = AccessionIssuanceRun.undismissed_for(current_actor).find(params[:id])

      run.dismiss!

      redirect_back fallback_location: admin_submission_requests_path
    end
  end
end
