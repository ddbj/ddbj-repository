module Admin
  # The curator editors that write a submission's record through its patch
  # chain (Submission#append_update!).
  module RecordEditing
    extend ActiveSupport::Concern

    # The chain has no record to edit. An ST.26 submission keeps its record
    # beside the chain rather than in it, and the record page does not show
    # the editors for one, so this is reached only by a request the screen
    # does not make.
    class NoRecord < StandardError; end

    included do
      rescue_from NoRecord do
        submission = Submission.find(params[:submission_id])

        redirect_to admin_submission_request_path(submission.request),
                    alert: 'Cannot edit: this submission has no record in its patch chain.'
      end
    end

    private

    # A copy of the record to edit, which the editor changes and hands to
    # append_update!.
    def editable_record(submission)
      submission.materialised_record&.deep_dup or raise NoRecord
    end
  end
end
