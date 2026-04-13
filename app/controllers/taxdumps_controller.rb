class TaxdumpsController < ApplicationController
  def show
    @names_count = Taxdump::Name.count
    @nodes_count = Taxdump::Node.count
    @loading     = LoadTaxdumpJob.loading?
  end

  def create
    unless current_user.admin?
      return render json: {error: 'Forbidden'}, status: :forbidden
    end

    path = Rails.root.join('storage/taxdump.tar.gz')

    unless path.exist?
      return render json: {error: 'storage/taxdump.tar.gz not found'}, status: :unprocessable_entity
    end

    LoadTaxdumpJob.perform_later

    render json: {message: 'Taxdump load enqueued'}, status: :accepted
  end
end
