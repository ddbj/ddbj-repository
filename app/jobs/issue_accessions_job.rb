# Runs AccessionIssue against one submission and records the outcome on
# the AccessionIssuance row the controller created.
#
# The whole point of it being a job is the Sequence row lock: it is held
# from allocation until the surrounding transaction commits, and that
# transaction now replays the chain and uploads a blob. Here, nobody is
# waiting on it.
class IssueAccessionsJob < ApplicationJob
  # A refusal is a decision, not a fault — the same failure would repeat
  # for ever. Anything else has already been reported by the time it gets
  # here, and re-running would re-enter the same lock. Both land on the
  # row so the curator reads the reason on the progress page rather than
  # watching a spinner that never resolves.
  discard_on StandardError do |job, error|
    issuance = AccessionIssuance.find_by(id: job.arguments.first[:issuance_id] || job.arguments.first['issuance_id'])

    issuance&.update!(status: 'failed', finished_at: Time.current,
                      error_message: "#{error.class}: #{error.message}")
  end

  def perform(issuance_id:)
    issuance = AccessionIssuance.find(issuance_id)

    # Two issuances on one submission would race for the same rows.
    # AccessionIssue would refuse the second on its own — every row it
    # targets already has an accession by then — but saying so here gives
    # the curator the reason rather than a puzzling refusal.
    if AccessionIssuance.where(submission_id: issuance.submission_id, status: 'running').where.not(id: issuance.id).exists?
      return issuance.update!(
        status:        'refused',
        finished_at:   Time.current,
        error_message: 'Another issuance is already running for this submission. Try again once it finishes.'
      )
    end

    result = AccessionIssue.call(
      submission: issuance.submission,
      actor:      issuance.actor,
      samples:    issuance.target_samples
    )

    issuance.update!(status: 'completed', accessions: result.accessions, finished_at: Time.current)
  rescue AccessionIssue::Refused => e
    issuance.update!(status: 'refused', finished_at: Time.current, error_message: e.message)
  end
end
