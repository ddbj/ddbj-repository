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
  end
end
