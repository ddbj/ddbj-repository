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
  end
end
