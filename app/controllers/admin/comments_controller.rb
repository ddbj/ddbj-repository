module Admin
  # Curator edit to the record-level free-text comments at v3
  # `submission.comments: list[str]`. Unlike ProjectsController (which
  # writes typed operational columns and bypasses the patch chain), this
  # edit goes THROUGH the patch chain via Submission#append_update! —
  # each save appends a SubmissionUpdate, the materialised cache
  # invalidates, and a curator can see the change in the show page's
  # patch-chain timeline.
  class CommentsController < ApplicationController
    def update
      submission = Submission.find(params[:submission_id])

      new_record = patched_record(submission, parse_body(params.dig(:submission_comments, :body)))

      result = submission.append_update!(
        new_record,
        actor:  "admin:#{current_user.uid}",
        source: :manual
      )

      message = result ? "Comments saved (chain length now #{submission.updates.count})." \
                       : 'Comments unchanged — no patch generated.'

      redirect_to admin_submission_path(submission), notice: message
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_path(submission),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    # Build the new record value to feed append_update!. We mutate a deep
    # copy of the current materialised_record so unrelated fields stay
    # identical (Canonicalizer.diff will then emit ops only for the
    # comments slot). If the resulting comments list is empty, drop the
    # key entirely to match the Converter's `.compact.reject(&:empty?)`
    # idiom — otherwise an empty array would round-trip through the
    # chain as a meaningful state.
    def patched_record(submission, comments)
      record = submission.materialised_record.deep_dup
      block  = record['submission'] ||= {}

      if comments.any?
        block['comments'] = comments
      else
        block.delete('comments')
      end

      record.delete('submission') if block.empty?
      record
    end

    # Textarea convention: one comment per non-blank line. Trim
    # surrounding whitespace; preserve internal whitespace verbatim.
    def parse_body(raw)
      return [] if raw.blank?

      raw.split(/\r?\n/).map(&:strip).reject(&:blank?)
    end
  end
end
