# Makes public what has reached its hold date — daily, as D-way's DRA
# ReleaseData did — for the databases taken over from D-way
# (`taken_over?`). Until a database is, D-way releases its data and the
# importer brings the status back, and a release here would only be undone
# by the next import.
#
# - A BioProject is released on its hold date, which D-way never did — it
#   had no date of its own. This system keeps one, and DistributionNotifier
#   tells the submitter ten days ahead that it will be released then.
# - A DRA submission is released on its hold date, and takes along what its
#   experiments are part of (DRA::LinkedRelease, from its publication).
# - A BioSample has no hold date.
#
# A hold date releases once. D-way cleared it on release; here it stays,
# as what the record says, so a row public since its hold date is not
# released by it again — one a curator has suppressed since stays
# suppressed.
#
# Each is released through Lifecycleable.move_to_status!, so the submitter
# is told as they are when a curator publishes it.
#
# Run again, it finds nothing it has released. A DRA submission and what it
# takes along are released in one transaction, so a run stopped between the
# two leaves neither.
class HoldDateRelease
  # What a hold date releases. Temporarily suppressed too: D-way released
  # those on their date as well.
  RELEASABLE_FROM = %w[private temporarily_suppressed].freeze

  # Some DRA submissions were not released: each is reported, and the run
  # says so as well, so it does not read as done.
  class Incomplete < StandardError; end

  Result = Data.define(:projects, :dra_submissions)

  def self.call(...) = new(...).call

  # Whether D-way has handed this database over: from then on its data is
  # released here.
  def self.taken_over?(db) = SubmissionRequest.submittable_dbs.include?(db)

  def initialize(today: Date.current)
    @today = today
  end

  def call
    projects = self.class.taken_over?('bioproject') ? due(Project).move_to_status!('public') : 0
    released = 0
    failed   = []

    if self.class.taken_over?('dra')
      due(DRASubmission).find_each do |row|
        # Due again at the write: a curator may have withdrawn it while
        # the run was reading other records.
        released += due(DRASubmission).where(id: row.id).move_to_status!('public')
      rescue Submission::MaterialisationFailed => e
        # A record that cannot be read holds back nothing else. Nothing of
        # this one was released, and the next run tries it again.
        Rails.error.report(e, handled: true, context: {dra_submission_id: row.id}, source: 'hold_date_release')

        failed << row.accession
      end
    end

    raise Incomplete, "Not released: #{failed.join(', ')}" if failed.any?

    Result.new(projects:, dra_submissions: released)
  end

  private

  # Not public since the start of its hold date, here: the timestamps are
  # kept in UTC and the date is Tokyo's.
  def due(model)
    model.where(status: RELEASABLE_FROM, hold_date: ..@today).where.not(accession: nil).where(<<~SQL.squish, tz: Time.zone.tzinfo.name)
      #{model.table_name}.last_published_at IS NULL OR
      #{model.table_name}.last_published_at < (#{model.table_name}.hold_date::timestamp AT TIME ZONE :tz) AT TIME ZONE 'UTC'
    SQL
  end
end
