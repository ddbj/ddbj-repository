module Admin
  class RegenerateFlatfilesController < ApplicationController
    def show
      @progress = RegenerateFlatfilesProgress.order(created_at: :desc).first
    end

    def create
      date        = Date.parse(params[:date])
      force       = ActiveModel::Type::Boolean.new.cast(params[:force]) || false
      submissions = Submission.where.associated(:ddbj_record_attachment)

      progress = RegenerateFlatfilesProgress.create!(total: submissions.count)

      ActiveJob.perform_all_later submissions.map {|submission|
        RegenerateSubmissionFlatfilesJob.new(submission, current_user, progress, date, force:)
      }

      redirect_to admin_regenerate_flatfiles_path, notice: 'Flatfile regeneration started.', status: :see_other
    end
  end
end
