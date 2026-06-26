module Admin
  # Curator edit for Submission#curator_comment, a typed AR text column
  # holding an internal note visible only to other curators. It lives
  # outside the DDBJ Record contract (the v3 record never carries it),
  # so the edit bypasses the patch chain entirely — same pattern as
  # ProjectsController's typed-column writes.
  class CuratorCommentsController < ApplicationController
    def update
      submission = Submission.find(params[:submission_id])

      # `update_columns` bypasses Submission's `validates :ddbj_record,
      # attached: true, on: :update` — that validation guards user-facing
      # submission flows, not curator-internal typed-column writes.
      # Mirrors how the BS Importer touches typed columns (sync_samples!
      # and the curator_comment sync both use update_columns).
      submission.update_columns(curator_comment: params.dig(:submission_curator_comment, :body).presence)

      redirect_to admin_submission_path(submission), notice: 'Curator comment saved.'
    end
  end
end
