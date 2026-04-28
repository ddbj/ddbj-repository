module Admin
  class SubmissionsController < ApplicationController
    def index
      pagy, @submissions = pagy(
        Submission.where(db: params[:db]).joins(request: :user).includes(request: :user).order(id: :desc)
      )

      response.headers.merge! pagy.headers_hash
    end
  end
end
