module Admin
  class RegenerateFlatfilesController < ApplicationController
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
      force       = ActiveModel::Type::Boolean.new.cast(params[:force]) || false
      submissions = Submission.where.associated(:ddbj_record_attachment)

      progress = RegenerateFlatfilesProgress.create!(total: submissions.count)

      ActiveJob.perform_all_later submissions.map {|submission|
        RegenerateSubmissionFlatfilesJob.new(submission, current_user, progress, date, force:)
      }

      render json: {}, status: :accepted
    end
  end
end
