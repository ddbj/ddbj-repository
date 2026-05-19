module Admin
  class SubmissionRequestsController < ApplicationController
    def index
      scope = SubmissionRequest.includes(:user).order(id: :desc)
      scope = scope.where(db: params[:db])                       if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?

      pagy, @requests = pagy(scope)

      response.headers.merge! pagy.headers_hash
    end
  end
end
