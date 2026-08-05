# One row per "curator uploaded a sample-attributes TSV" attempt.
# Created by Admin::SampleTSVImportsController#create, then owned by
# ImportSampleTSVJob which writes progress + the final terminal state.
#
# Read-only from the curator's perspective: the show page polls this
# row to render progress, and offers the error_report (if any) as a
# download once status flips off `running`.
class SampleTSVImport < ApplicationRecord
  STATUSES = %w[running completed failed].freeze

  belongs_to :submission

  enum :status, STATUSES.index_with(&:itself), suffix: :status, validate: true

  validates :actor, presence: true

  scope :recent, -> { order(started_at: :desc) }

  # Mirrors RegenerateFlatfilesRun's loading?/completed? semantics
  # — UI polls until one of these flips. `failed` rows still count as
  # "completed" so the progress bar doesn't hang on a totally broken
  # input.
  def loading?
    running_status?
  end

  def completed?
    !running_status?
  end

  # Which half of the work is running. Checking is row by row and
  # countable; applying is a single transaction, so it reports what it is
  # about to write and nothing more — see the migration.
  def checking? = phase == 'checking'

  def applying? = phase == 'applying'

  # How the job marks a failure that was a crash rather than something
  # wrong with the file. Owned here because two readers depend on it: the
  # job writes it, and the result screen decides from it whether to say
  # developers already know.
  ABORT_PREFIX = 'Job aborted: '.freeze

  # The other way an import fails without the file being at fault. Owned
  # here for the same reason as ABORT_PREFIX: the job writes it and the
  # screen reads it, and "fix the file" is the wrong instruction for a
  # curator whose file is fine and whose move is to wait.
  CONFLICT_MESSAGE = 'Another sample TSV import is already running for this submission. ' \
                     'Try again once it finishes.'.freeze

  # A crash we reported, as opposed to a file the curator can fix. The
  # screen promises a notification only for the first, and only because
  # ImportSampleTSVJob actually sends one.
  def reported? = failed_status? && error_report.to_s.start_with?(ABORT_PREFIX)

  def conflicted? = failed_status? && error_report == CONFLICT_MESSAGE

  # Three terminal readings, and the difference between them is the
  # question a curator actually has: is my submission half-changed?
  #
  #   completed, no rejections — everything landed
  #   completed, some rejected — the rest landed, and are live
  #   failed                   — nothing landed; one transaction, so
  #                              there is no half-applied state
  def outcome
    return :failed if failed_status?

    failed.positive? ? :partial : :clean
  end
end
