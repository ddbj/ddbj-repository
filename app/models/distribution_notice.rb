# One release notice, as sent — or as not sent, and why.
#
# The screen's central question is "was this submitter told?", and until
# this table existed nothing could answer it: `distribution_notified_at`
# on the project says a mail was attempted at some point, not who received
# what, on whose authority, or whether it went anywhere.
#
# Append-only. Rows are never edited; a correction is another row.
class DistributionNotice < ApplicationRecord
  TRIGGERS = %w[scheduled manual].freeze
  RESULTS  = %w[delivered skipped].freeze

  # Why nothing was sent. Only one reason so far, but naming it beats a
  # bare `skipped` that the reader has to guess at.
  NO_ADDRESS = 'no_address'

  belongs_to :user

  enum :trigger, TRIGGERS.index_with(&:itself), suffix: true, validate: true
  enum :result,  RESULTS.index_with(&:itself),  suffix: true, validate: true

  scope :recent, -> { order(sent_at: :desc, id: :desc) }
  scope :since,  ->(time) { where(sent_at: time..) }

  # The automation strip reports the daily job, not a curator's manual
  # send — the two interleave, and "when did the schedule last run" is a
  # question about the schedule.
  scope :last_scheduled_run, -> {
    at = scheduled_trigger.maximum(:sent_at) or return none

    scheduled_trigger.where(sent_at: at)
  }

  # A submitter with no address stays in the due list indefinitely, so the
  # useful number is how long it has been that way. Taken from the first
  # skip rather than from the project, because the block starts when we
  # first tried and could not.
  scope :blocked, -> { skipped_result.where(skip_reason: NO_ADDRESS) }

  def self.blocked_since(user_ids)
    blocked.where(user_id: user_ids).group(:user_id).minimum(:sent_at)
  end

  # Who to credit. `scheduled` has no actor by design: nobody pressed
  # anything, and naming a curator would misattribute it.
  def trigger_label
    manual_trigger? ? "Manual · #{actor.to_s.split(':', 2).last}" : 'Scheduled'
  end
end
