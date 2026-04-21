module Admin
  class RegenerateFlatfilesController < ApplicationController
    before_action :require_admin!

    def show
      progress = RegenerateFlatfilesProgress.order(created_at: :desc).first

      render json: {
        loading:   progress ? progress.processed < progress.total : false,
        total:     progress&.total,
        processed: progress&.processed
      }
    end

    def create
      date        = Date.parse(params[:date])
      submissions = Submission.where.associated(:ddbj_record_attachment)

      progress = RegenerateFlatfilesProgress.create!(total: submissions.count)

      ActiveJob.perform_all_later submissions.map {|submission|
        RegenerateSubmissionFlatfilesJob.new(submission, current_user, progress, date)
      }

      render json: {}, status: :accepted
    end

    private

    def require_admin!
      head :forbidden unless current_user&.admin?
    end
  end
end
