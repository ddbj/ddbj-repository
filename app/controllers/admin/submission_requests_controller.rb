module Admin
  class SubmissionRequestsController < ApplicationController
    def index
      scope = SubmissionRequest.includes(:user).order(id: :desc)
      scope = scope.where(db: params[:db])              if params[:db].presence
      scope = scope.joins(:user).where(users: {uid: params[:user]}) if params[:user].presence

      pagy, @requests = pagy(scope)

      response.headers.merge! pagy.headers_hash
    end
  end
end
