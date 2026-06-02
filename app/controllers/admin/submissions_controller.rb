module Admin
  class SubmissionsController < ApplicationController
    def index
      scope = Submission.includes(:user).order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?

      @pagy, @submissions = pagy(scope)
    end

    def show
      @submission = Submission.includes(:user, :updates).find(params[:id])
      @updates    = @submission.updates.order(:id)
      @as_of      = params[:as_of].presence&.to_i
      @as_of_row  = @as_of && @updates.find {|u| u.id == @as_of }

      @materialised    = @submission.materialise_at(update_id: @as_of)
      @canonical_bytes = @materialised && DDBJRecord::Canonicalizer.canonicalize(@materialised)
      @sha256          = @materialised && DDBJRecord::Canonicalizer.sha256(@materialised)
    end
  end
end
