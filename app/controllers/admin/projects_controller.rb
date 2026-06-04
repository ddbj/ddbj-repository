module Admin
  # Curator edits to a BP submission's Project row: status (Lifecycleable
  # 9-state enum) and assignee (admin user). The Project itself is operational
  # state — these writes do NOT generate SubmissionUpdate patches; content
  # edits go through a different path (Phase A PR 2).
  class ProjectsController < ApplicationController
    def update
      submission = Submission.find(params[:submission_id])
      project = submission.project or raise ActiveRecord::RecordNotFound

      # `with_lock` opens (or reuses) a transaction + `SELECT ... FOR UPDATE`.
      # Two curators clicking Update at the same moment serialise; last writer
      # wins, but neither writer sees a stale row.
      project.with_lock do
        project.update!(project_params)
      end

      redirect_to admin_submission_path(submission),
                  notice: "Project updated: status=#{project.status}, assignee=#{project.assignee&.uid || '—'}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_submission_path(submission), alert: "Project update failed: #{e.message}"
    end

    private

    def project_params
      params.expect(project: %i[status assignee_id])
    end
  end
end
