module Admin
  class SubmissionRequestsController < ApplicationController
    def index
      pagy, @requests = pagy(SubmissionRequest.where(db: params[:db]).includes(:user).order(id: :desc))

      response.headers.merge! pagy.headers_hash
    end
  end
end
