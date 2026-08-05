# One press of Regenerate, and everything it covered.
#
# The tool used to keep a single progress row: three counters, no actor,
# no scope. That answered "is something running" and nothing else — not
# who started the run that rewrote every flatfile last month, not what it
# was pointed at, and not which submissions it failed on. A run records
# what it was asked to do, so the answer survives the next press.
class RegenerateFlatfilesRun < ApplicationRecord
  # What the run was pointed at. `retry` is its own target rather than a
  # flag on `accessions`, because the set it covers is "whatever failed
  # last time" — it cannot be re-derived from a list of numbers.
  TARGETS = %w[accessions all retry].freeze

  # A run whose workers are gone. Every increment touches the row, so an
  # hour of silence with jobs outstanding is not a slow queue — it is a
  # queue that is no longer being served. Without this bound the screen
  # polls itself for ever and the run never reaches a result.
  STALE_AFTER = 1.hour

  belongs_to :retry_of, class_name: 'RegenerateFlatfilesRun', optional: true

  has_many :retries,  class_name: 'RegenerateFlatfilesRun', foreign_key: :retry_of_id,
                      inverse_of: :retry_of, dependent: :nullify
  has_many :failures, -> { order(:id) }, class_name: 'RegenerateFlatfilesFailure', foreign_key: :run_id,
                                         inverse_of: :run, dependent: :delete_all

  enum :target, TARGETS.index_with(&:itself), suffix: true, validate: true

  validates :actor, presence: true

  scope :recent,   -> { order(started_at: :desc) }
  scope :finished, -> { where.not(finished_at: nil) }

  # How long a submission takes, measured rather than assumed. The
  # estimate on the form is worth showing only because it comes from what
  # this installation actually did — a constant compiled in here would be
  # wrong on the first machine that is not the one it was written on, and
  # would stay wrong silently. Nil until there is a finished run to
  # measure, and the screens then say nothing rather than guessing.
  def self.measured_rate
    rows = finished.where('regenerated + skipped + failed > 0').recent.limit(5).to_a
    return nil if rows.empty?

    rows.sum(&:seconds_per_submission) / rows.size
  end

  # Enough failures to recognise what went wrong without turning the
  # panel into a log. The rest is what the download is for.
  SHOWN_FAILURES = 5

  def shown_failures = failures.limit(SHOWN_FAILURES)

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  def done = regenerated + skipped + failed

  def remaining = [total - done, 0].max

  def percent = total.zero? ? 100 : done * 100 / total

  # Still being worked on. A run that stopped moving is not loading, so
  # the screen shows what it got through instead of a bar that never
  # fills — see STALE_AFTER.
  def loading? = finished_at.nil? && !stale?

  def completed? = !loading?

  def stale? = finished_at.nil? && updated_at < STALE_AFTER.ago

  def elapsed = (finished_at || updated_at) - started_at

  def seconds_per_submission = done.positive? ? elapsed / done : 0

  # Seconds of work left at the rate this run has managed so far. Its own
  # rate, not the historical one: a run that is going slowly today should
  # say so.
  def eta
    return nil unless loading? && done.positive? && remaining.positive?

    seconds_per_submission * remaining
  end

  # Three readings, and the difference between them is what a curator
  # came to the screen for:
  #
  #   :clean   — everything it covered is regenerated or deliberately skipped
  #   :partial — some submissions failed; the rest are live
  #   :stalled — the workers went away, so the counts are all there is
  def outcome
    return :stalled if stale?

    failed.positive? ? :partial : :clean
  end

  def scope_label
    case target
    when 'all'   then 'All submissions'
    when 'retry' then "Retry of ##{retry_of_id}"
    else              "#{number_list.size} #{'accession'.pluralize(number_list.size)}"
    end
  end

  def number_list = numbers.to_s.split(/[\s,]+/).reject(&:blank?)

  # Records a failure and counts it in one go, so the row and the counter
  # cannot disagree — a screen that says "6 failed" and lists five is a
  # screen nobody trusts twice.
  def record_failure!(submission, error)
    transaction do
      failures.create!(
        submission: submission,
        label:      submission && (submission.accessions.order(:id).first&.number || submission.source_id),
        message:    "#{error.class}: #{error.message}"
      )

      increment! :failed, touch: true
    end

    finish_if_done!
  end

  def count!(counter)
    increment! counter, touch: true

    finish_if_done!
  end

  # Stamped by whichever job happens to be last. Guarded on `finished_at
  # IS NULL` and run as one statement, so the twenty workers that finish
  # at once cannot each write their own idea of when the run ended.
  def finish_if_done!
    self.class
        .where(id:, finished_at: nil)
        .where('regenerated + skipped + failed >= total')
        .update_all(finished_at: Time.current, updated_at: Time.current)
  end
end
