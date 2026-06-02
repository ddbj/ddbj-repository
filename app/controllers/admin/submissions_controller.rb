module Admin
  class SubmissionsController < ApplicationController
    def index
      scope = Submission.includes(request: :user).order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?

      if params[:user].present?
        scope = scope.where(request: SubmissionRequest.where(user: User.where(uid: params[:user])))
      end

      @pagy, @submissions = pagy(scope)
    end

    def show
      @submission         = Submission.includes(:user, :updates, :project).find(params[:id])
      @materialised       = @submission.materialised_record
      @canonical_bytes    = @materialised && DDBJRecord::Canonicalizer.canonicalize(@materialised, for_diff: false)
      @sha256             = @materialised && DDBJRecord::Canonicalizer.sha256(@materialised, for_diff: true)
    end
  end
end
