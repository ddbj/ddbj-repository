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

  scope :blocked, -> { skipped_result.where(skip_reason: NO_ADDRESS) }

  # A submitter with no address stays in the due list indefinitely, so the
  # useful number is how long it has been that way — measured from the
  # start of the CURRENT block, not from the first one ever. Somebody who
  # was unreachable last year, gave us an address, and has gone quiet
  # again has been blocked for a week, not for a year.
  def self.blocked_since(user_ids)
    return {} if user_ids.empty?

    blocked
      .where(user_id: user_ids)
      .where(<<~SQL.squish)
        distribution_notices.sent_at > COALESCE(
          (SELECT MAX(delivered.sent_at)
           FROM   distribution_notices delivered
           WHERE  delivered.user_id = distribution_notices.user_id
             AND  delivered.result  = 'delivered'),
          '-infinity'
        )
      SQL
      .group(:user_id)
      .minimum(:sent_at)
  end

  # Already known to be unreachable, and nothing has got through since.
  # The daily run would otherwise write an identical skip every morning
  # for as long as the hold date stays in the window, filling the history
  # that exists to answer "was this submitter told?" with the same answer
  # ten times.
  def self.currently_blocked_user_ids(user_ids)
    blocked_since(user_ids).keys.to_set
  end

  # Who to credit. `scheduled` has no actor by design: nobody pressed
  # anything, and naming a curator would misattribute it. A manual send
  # with no actor recorded says just "Manual" rather than trailing a
  # separator with nothing after it.
  def trigger_label
    return 'Scheduled' unless manual_trigger?

    who = actor.to_s.split(':', 2).last.presence

    who ? "Manual · #{who}" : 'Manual'
  end
end
