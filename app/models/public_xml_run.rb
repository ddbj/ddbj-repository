# One row per public-XML output run. PublicXML::Exporter creates it at the
# start of a run and stamps `finished_at` / counters on completion, for
# PublishBpXMLJob, PublishBsXMLJob and PublishBpExchangeXMLJob.
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

  # Runs the block as the only run of its db and kind, or not at all while
  # another is running. A row left `running` cannot say which: a live run
  # and one whose process was stopped under it (by a deploy, or with its
  # host) leave the same row. The lock can (AdvisoryLock), so what holds it
  # ends what a stopped run left.
  #
  # Not run at all rather than waited for: the next scheduled run writes
  # the file anyway.
  def self.exclusively(db:, kind:)
    AdvisoryLock.exclusively "public_xml_run:#{db}:#{kind}" do
      where(db:, kind:, status: 'running').find_each do |run|
        run.update!(status: 'failed', finished_at: Time.current)
        run.append_error!('Stopped before it finished.')
      end

      yield
    end
  rescue AdvisoryLock::Held => e
    Rails.logger.info "Not writing #{db} #{kind} XML: #{e.message}"

    nil
  end

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
