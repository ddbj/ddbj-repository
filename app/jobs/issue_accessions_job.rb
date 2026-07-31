# Runs AccessionIssue against one submission and records the outcome on
# the AccessionIssuance row the controller created.
#
# The whole point of it being a job is the Sequence row lock: it is held
# from allocation until the surrounding transaction commits, and that
# transaction now replays the patch chain and uploads a blob. Here,
# nobody is waiting on it.
class IssueAccessionsJob < ApplicationJob
  # A fault is not retried: re-running would re-enter the same lock, and
  # the transaction rolled everything back, so the recovery a curator
  # wants is to look at what went wrong and press the button again. What
  # they cannot do is notice a job that vanished — hence both the row and
  # the report.
  discard_on StandardError do |job, error|
    issuance = AccessionIssuance.find_by(id: job_kwarg(job, :issuance_id))

    issuance&.update!(status: 'failed', finished_at: Time.current,
                      error_message: "#{error.class}: #{error.message}")

    Rails.error.report(error, handled: true, source: 'issue_accessions_job')
  end

  def perform(issuance_id:)
    issuance = AccessionIssuance.find(issuance_id)

    return unless claim(issuance)

    result = AccessionIssue.call(
      submission: issuance.submission,
      actor:      issuance.actor,
      samples:    issuance.target_samples
    )

    issuance.update!(status: 'completed', accessions: result.accessions, finished_at: Time.current)

    # Issuing is editing, so it puts the curator in the request's
    # participants — but only now that it has happened. Pressing a button
    # that turned out to be refused is not work on the request.
    issuance.submission.request&.participate!(issuance.curator)
  # Only a refusal is caught here. A broken chain (AccessionIssue::
  # ChainBroken) deliberately falls through to `discard_on`, so it is
  # recorded as failed and reported — a submission whose history cannot
  # be replayed is not an ineligible submission, and the grey Skipped
  # badge it used to get told nobody anything.
  rescue AccessionIssue::Refused => e
    issuance.update!(status: 'refused', finished_at: Time.current, error_message: e.message)
  end

  private

  # Take the submission, or say why not.
  #
  # Two issuances on one submission would race for the same rows.
  # AccessionIssue would refuse the second on its own — every row it
  # targets already has an accession by then — but saying so here gives
  # the curator the reason rather than a puzzling refusal.
  #
  # The check and the claim happen under a lock on the submission, so a
  # double-click cannot have both jobs see the other as running and
  # refuse each other into a standstill.
  def claim(issuance)
    issuance.submission.with_lock do
      if AccessionIssuance.running_for(issuance.submission).where.not(id: issuance.id).exists?
        issuance.update!(
          status:        'refused',
          finished_at:   Time.current,
          error_message: 'Another issuance is already running for this submission. Try again once it finishes.'
        )

        next false
      end

      issuance.update!(status: 'running')

      true
    end
  end
end
