class AccessionRenewalsController < ApplicationController
  def show
    @renewal = current_user.accession_renewals.find(params.expect(:id))
  end

  def create
    accession = current_user.accessions.find_by!(number: params.expect(:accession_number))
    @renewal  = accession.renewals.create!(renewal_params)

    RenewAccessionJob.perform_later @renewal

    render :show, status: :accepted
  end

  private

  def renewal_params
    params.expect(accession_renewal: [
      :file
    ])
  end
end
