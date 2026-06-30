module Admin
  class RegenerateFlatfilesController < ApplicationController
    def show
      @progress = RegenerateFlatfilesProgress.order(created_at: :desc).first
    end

    def create
      date  = params[:date].presence && Date.parse(params[:date])
      force = ActiveModel::Type::Boolean.new.cast(params[:force]) || false

      # The cache snapshot now lives in ActiveStorage so it isn't on
      # the submissions row — no bytea projection trick needed any more.
      submissions = Submission.where.associated(:ddbj_record_attachment)

      if params[:numbers].present?
        numbers     = params[:numbers].split(/[\s,]+/).reject(&:blank?)
        submissions = submissions.where(id: Accession.where(number: numbers).select(:submission_id))
      end

      progress = RegenerateFlatfilesProgress.create!(total: submissions.count)

      ActiveJob.perform_all_later submissions.map {|submission|
        RegenerateSubmissionFlatfilesJob.new(submission, current_user, progress, date, force:)
      }

      redirect_to admin_regenerate_flatfiles_path,
                  notice: "Flatfile regeneration started for #{progress.total} submission(s).",
                  status: :see_other
    end
  end
end
