module Admin
  class SubmissionsController < ApplicationController
    def index
      scope = Submission.includes(:user).order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?

      @pagy, @submissions = pagy(scope)
    end

    def show
      @submission      = Submission.includes(:user).find(params[:id])
      @materialised    = @submission.materialised_record
      @canonical_bytes = @materialised && DDBJRecord::Canonicalizer.canonicalize(@materialised)
      @sha256          = @materialised && DDBJRecord::Canonicalizer.sha256(@materialised)
    end
  end
end
