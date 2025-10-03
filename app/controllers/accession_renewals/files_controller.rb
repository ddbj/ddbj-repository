class AccessionRenewals::FilesController < ApplicationController
  def show
    renewal = current_user.accession_renewals.find(params.expect(:accession_renewal_id))

    redirect_to renewal.file.url, allow_other_host: true
  end
end
