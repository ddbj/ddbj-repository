# One row per public-XML output run. Owned by PublishBpXmlJob /
# PublishBsXmlJob, which create the row at the start of a run and stamp
# `finished_at` / counters on completion.
#
# `kind = 'exchange'` is BP-only — the BS pipeline has no 三極交換用 XML
# in the legacy bsbatch implementation, so we refuse it at the model
# layer rather than silently producing an empty file.
#
# A subsequent Phase B exchange run reads the most recent finished
# `public` run's `started_at` as `lastRun` for ADD/UPDATE/UNCHANGE
# delta calculation. Storing `started_at` (rather than `finished_at`)
# matches the legacy bpbatch contract: a record released *during* a
# run still counts as eAdded next time around.
class PublicXMLRun < ApplicationRecord
  DBS   = %w[bioproject biosample].freeze
  KINDS = %w[public exchange].freeze

  enum :status, {
    running:   'running',
    completed: 'completed',
    failed:    'failed'
  }, suffix: true, validate: true

  validates :db,   presence: true, inclusion: {in: DBS}
  validates :kind, presence: true, inclusion: {in: KINDS}

  validate :exchange_is_bioproject_only

  scope :recent, -> { order(started_at: :desc) }

  def self.previous_public_run(db:)
    where(db:, kind: 'public', status: 'completed').recent.first
  end

  # Mirrors MigrationRun#append_error! — `error_log` is a `text` column,
  # callers append one line per failure (Phase B exchange runs may
  # accumulate several across delta judgments).
  def append_error!(message)
    return if message.blank?

    reload
    update!(error_log: [error_log, message].compact_blank.join("\n"))
  end

  private

  def exchange_is_bioproject_only
    return unless kind == 'exchange' && db != 'bioproject'

    errors.add(:kind, 'exchange is only valid for bioproject')
  end
end
