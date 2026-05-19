module Admin
  class SubmissionsController < ApplicationController
    def index
      scope = Submission.joins(request: :user).includes(request: :user).order(id: :desc)
      scope = scope.where(db: params[:db])           if params[:db].presence
      scope = scope.where(users: {uid: params[:user]}) if params[:user].presence

      pagy, @submissions = pagy(scope)

      response.headers.merge! pagy.headers_hash
    end
  end
end
