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

  # Mirrors RegenerateFlatfilesProgress's loading?/completed? semantics
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
