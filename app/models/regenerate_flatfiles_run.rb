# One press of Regenerate, and everything it covered.
#
# The tool used to keep a single progress row: three counters, no actor,
# no scope. That answered "is something running" and nothing else — not
# who started the run that rewrote every flatfile last month, not what it
# was pointed at, and not which submissions it failed on. A run records
# what it was asked to do, so the answer survives the next press.
class RegenerateFlatfilesRun < ApplicationRecord
  # What the run was pointed at. `retry` is its own target rather than a
  # flag on `entries`, because the set it covers is "whatever failed
  # last time" — it cannot be re-derived from a list of numbers.
  TARGETS = %w[accessions all retry].freeze

  # `force` is a retired option: runs made before dates were written by
  # accession could be told to rewrite files whose content had not
  # changed, because a date was applied only to what the comparison had
  # already called changed — so setting one without it did nothing.
  #
  # Nothing reads the column, and nothing ever set it but that option, so
  # it is only the `true` rows that still say anything. It is kept for
  # them; the column is a candidate for dropping once they stop being
  # interesting.

  # How long a run may report nothing before it stops being believed.
  #
  # It is deliberately not read as "the workers are gone": a run queued
  # behind a long migration has never touched its row either, and saying
  # its jobs are lost would invite a second run over the same
  # submissions. What it does is stop the screen polling for ever, and
  # stop one silent run blocking every later one.
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

  # What a second press has to wait for. Two runs over the same
  # submission put two workers on the same record: both rewrite the
  # flatfile, both overwrite `entries.locus_date`, and both write an
  # accession history entry. The stale bound is the escape — a run that
  # reports nothing for an hour stops blocking later ones, or one dead
  # worker would close the tool for good.
  scope :in_flight, -> { where(finished_at: nil, updated_at: STALE_AFTER.ago..) }

  # How long a submission takes, measured rather than assumed. The
  # estimate on the form is worth showing only because it comes from what
  # this installation actually did — a constant compiled in here would be
  # wrong on the first machine that is not the one it was written on, and
  # would stay wrong silently. Nil until there is a finished run to
  # measure, and the screens then say nothing rather than guessing.
  def self.measured_rate
    rows = finished.where('regenerated + skipped + failed > 0').recent.limit(5).to_a
    return nil if rows.empty?

    # Weighted by what each run actually got through, not one vote per
    # run. Most runs are two or three accessions whose elapsed time is
    # mostly queue latency; averaging their rates with a thousand-record
    # run's would put a number an order of magnitude high next to the
    # most destructive control on the screen.
    rows.sum(&:elapsed) / rows.sum(&:done)
  end

  # Enough failures to recognise what went wrong without turning the
  # panel into a log. The rest is what the download is for.
  SHOWN_FAILURES = 5

  def shown_failures = failures.limit(SHOWN_FAILURES)

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  def done = regenerated + skipped + failed

  def remaining = [total - done, 0].max

  def percent = total.zero? ? 100 : done * 100 / total

  # Not finished. A run that has gone quiet is still loading — it may be
  # queued behind something long — so it keeps its progress reading
  # rather than being declared over on a timer.
  def loading? = finished_at.nil?

  def completed? = !loading?

  # Reporting nothing for long enough that the screen stops asking. Says
  # only that: whether the jobs are lost or merely waiting is not
  # something this row knows.
  def stale? = finished_at.nil? && updated_at < STALE_AFTER.ago

  def elapsed = (finished_at || updated_at) - started_at

  def seconds_per_submission = done.positive? ? elapsed / done : 0

  # Enough completions that the wait before the first one stopped
  # dominating. `started_at` is when the jobs were enqueued, not when one
  # first ran, so with a single completion the rate is however long the
  # queue happened to be — and the panel refreshes every three seconds,
  # which is often enough for somebody to read it.
  MIN_SAMPLE = 20

  # Seconds of work left at the rate this run has managed so far. Its own
  # rate, not the historical one: a run that is going slowly today should
  # say so.
  #
  # Elapsed is measured to the last progress rather than to now, so a run
  # whose workers went away freezes its estimate instead of inflating it.
  # `[MIN_SAMPLE, total]` rather than MIN_SAMPLE flat: a run of twenty or
  # fewer could never satisfy both the sample size and "there is anything
  # left", so it showed no estimate for its whole life rather than only
  # at the start of it.
  def eta
    return nil unless loading? && done >= [MIN_SAMPLE, total].min && remaining.positive?

    seconds_per_submission * remaining
  end

  # Two readings of a finished run, and the difference between them is
  # what a curator came to the screen for: everything it covered is
  # regenerated or deliberately skipped, or some of it failed and the
  # rest is live.
  def outcome = failed.positive? ? :partial : :clean

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
  #
  # `label` takes what it can get: a submission that has been destroyed
  # is exactly the case where the job could not even read its arguments,
  # and "the run failed on something" is not a report.
  def record_failure!(submission, error, label: nil)
    label ||= self.class.label_for(submission)

    # A submission destroyed while its job was in flight: the row it
    # points at is gone, so storing the reference would fail on the
    # foreign key — inside the failure handler, where it would replace
    # the error being reported with one about the reporting. The label
    # is what the row is read by, and it is already in hand.
    submission = nil unless submission && Submission.exists?(submission.id)

    transaction do
      failures.create!(
        submission: submission,
        label:      label,
        message:    "#{error.class}: #{error.message}"
      )

      increment! :failed, touch: true
    end

    finish_if_done!
  end

  def self.label_for(submission)
    return 'unknown submission' unless submission

    submission.entries.order(:id).first&.accession.presence ||
      submission.source_id.presence ||
      "submission ##{submission.id}"
  end

  # Counts one submission's outcome, and takes back the failure it is
  # replacing. A job re-run from the queue browser lands here for a
  # submission this run has already counted as failed; without clearing
  # it the run reports more outcomes than it has submissions, and goes
  # on naming a failure that has since succeeded.
  def count!(counter, submission)
    transaction do
      cleared = failures.where(submission_id: submission.id).delete_all

      self.class.update_counters(id, failed: -cleared) if cleared.positive?

      increment! counter, touch: true
    end

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
