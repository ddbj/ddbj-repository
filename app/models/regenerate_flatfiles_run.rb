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
  #
  # `submission` likewise. Naming one of a submission's accessions would
  # cover it — a flatfile belongs to a submission, so any of these runs
  # rewrites whole files — but it would sit here as a run that named
  # accessions, which is neither what was asked for nor what a retry of
  # it should do.
  TARGETS = %w[accessions submission all retry].freeze

  # How long a run may report nothing before it stops being believed.
  #
  # It is deliberately not read as "the workers are gone": a run queued
  # behind a long migration has never touched its row either, and saying
  # its jobs are lost would invite a second run over the same
  # submissions. What it does is stop the screen polling for ever, and
  # stop one silent run blocking every later one.
  STALE_AFTER = 1.hour

  belongs_to :retry_of, class_name: 'RegenerateFlatfilesRun', optional: true

  # The submission a run of one submission was about, and the one a retry
  # of such a run is still about. Null for the paste and for the
  # every-submission run, neither of which is about one.
  belongs_to :submission, optional: true

  has_many :retries,  class_name: 'RegenerateFlatfilesRun', foreign_key: :retry_of_id,
                      inverse_of: :retry_of, dependent: :nullify
  has_many :failures, -> { order(:id) }, class_name: 'RegenerateFlatfilesFailure', foreign_key: :run_id,
                                         inverse_of: :run, dependent: :delete_all

  enum :target, TARGETS.index_with(&:itself), suffix: true, validate: true

  validates :actor, presence: true

  # How the pasted list is read, wherever it is read. `RegenerationScope`
  # runs these numbers and this row reports how many there were, and a
  # run that says "2 accessions" beside a list a retry resolves to three
  # is a run nobody can check.
  SEPARATOR = /[\s,]+/

  def self.parse_numbers(text) = text.to_s.split(SEPARATOR).reject(&:blank?).uniq

  # The count every screen reads, kept from the list only a retry reads.
  # Derived here rather than passed in, so a run written from anywhere —
  # the controller, a console, a test — carries the count of its own list.
  #
  # The guard is what makes this compatible with `without_numbers`: on a
  # row loaded without the column, reading `numbers` raises
  # `ActiveModel::MissingAttributeError`, and the panel controller saves
  # such rows. It is not about the counter writes during a run — those go
  # through `update_counters` and `update_all`, which fire no callbacks
  # at all.
  #
  # `has_attribute?` rather than `will_save_change_to_numbers?`, so the
  # count is recomputed even when only the count was assigned. That costs
  # one 40 ms split per save of a full row, and a run is saved twice.
  before_save :count_accessions, if: -> { has_attribute?(:numbers) }

  scope :recent,   -> { order(started_at: :desc) }
  scope :finished, -> { where.not(finished_at: nil) }

  # Without the accession list. A bulk paste is over a megabyte — 127,604
  # numbers is 1.1 MB — and the only thing that reads it back is a retry.
  # Every other reader wants the count, which `accession_count` carries.
  #
  # The progress panel is why this is a scope rather than a habit: it
  # polls its own run every three seconds for the length of the run, so
  # loading the column there meant detoasting a megabyte and splitting it
  # into 127,604 strings six hundred times over a half-hour regeneration
  # — inside the Puma process that is also running the jobs.
  scope :without_numbers, -> { select(column_names - ['numbers']) }

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
    # Five whole rows, of which this reads six integers and three
    # timestamps — and it is called from the summary partial, which the
    # preview endpoint re-renders while somebody is pasting the list.
    rows = without_numbers.finished.where('regenerated + skipped + failed > 0').recent.limit(5).to_a
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
    when 'all'        then 'All submissions'
    when 'retry'      then "Retry of ##{retry_of_id}"
    when 'submission' then "Submission ##{submission_id}"
    # Delimited here rather than by the view, because the label is one
    # phrase and its branches should not be assembled two different ways.
    # Six figures is the ordinary size of one of these runs.
    else              "#{ActiveSupport::NumberHelper.number_to_delimited(accession_count)} #{'accession'.pluralize(accession_count)}"
    end
  end

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

  private

  def count_accessions
    self.accession_count = self.class.parse_numbers(numbers).size
  end
end
