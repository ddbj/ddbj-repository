module Admin
  class RegenerateFlatfilesController < ApplicationController
    def show
      @progress = RegenerateFlatfilesProgress.order(created_at: :desc).first
    end

    def create
      date  = params[:date].presence && Date.parse(params[:date])
      force = ActiveModel::Type::Boolean.new.cast(params[:force]) || false

      # Project away the bytea cache column on the .map side: at BS
      # scale the cumulative bytea (~7MB × N) would spike Puma worker
      # RSS into the GB range before perform_all_later runs. The count
      # uses the unprojected relation — Postgres COUNT(specific
      # columns) is a different aggregate signature than COUNT(*).
      submissions = Submission.where.associated(:ddbj_record_attachment)

      if params[:numbers].present?
        numbers     = params[:numbers].split(/[\s,]+/).reject(&:blank?)
        submissions = submissions.where(id: Accession.where(number: numbers).select(:submission_id))
      end

      progress = RegenerateFlatfilesProgress.create!(total: submissions.count)

      ActiveJob.perform_all_later submissions
        .select(Submission.column_names - %w[cached_materialised_record])
        .map {|submission|
          RegenerateSubmissionFlatfilesJob.new(submission, current_user, progress, date, force:)
        }

      redirect_to admin_regenerate_flatfiles_path,
                  notice: "Flatfile regeneration started for #{progress.total} submission(s).",
                  status: :see_other
    end
  end
end
