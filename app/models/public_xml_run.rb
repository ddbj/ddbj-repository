# One row per public-XML output run. Owned by PublishBpXmlJob /
# PublishBsXmlJob, which create the row at the start of a run and stamp
# `finished_at` / counters on completion.
#
# `kind = 'exchange'` is BP-only — the BS pipeline has no 三極交換用 XML
# in the legacy bsbatch implementation, so we refuse it at the model
# layer rather than silently producing an empty file.
#
# The exchange run computes its eAdded/eUpdated/eUnchanged delta against
# the most recent finished run OF THE SAME KIND — i.e. the previous
# `exchange` run, NOT the previous `public` run. This matches legacy
# bpbatch, which keeps independent `lastRun_Public` / `lastRun_Collab`
# markers so the public dump and the three-pole exchange advance on
# their own cadences. Storing `started_at` (rather than `finished_at`)
# also matches bpbatch: a record released *during* a run still counts as
# eAdded next time around.
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

  # Most recent completed run of a given kind — the delta anchor for the
  # next run of that same kind (see the class comment).
  def self.previous_run(db:, kind:)
    where(db:, kind:, status: 'completed').recent.first
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
