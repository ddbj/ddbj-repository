class DRASubmission < ApplicationRecord
  include Lifecycleable

  # SRA for the 27 early submissions D-way numbers under that prefix.
  ACCESSION_FORMAT = /\A[DS]RA\d{6,}\z/

  belongs_to :submission

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true

  # None for one imported from D-way: its status is D-way's, and the next
  # import would put back a status set here. One sent here is curated here.
  def self.settable_statuses_for(rows)
    rows.joins(:submission).where.not(submissions: {source_id: nil}).exists? ? [] : settable_statuses
  end

  # Published, a DRA submission takes along what its experiments are part
  # of (DRA::LinkedRelease) — however it is published, by its hold date or
  # by a curator.
  def self.move_to_status!(status, **)
    return super unless status.to_s == 'public'

    transaction do
      publishing = where.not(status: :public).lock.pluck(:submission_id)
      count      = super

      Submission.where(id: publishing).find_each { DRA::LinkedRelease.call(it) }

      count
    end
  end
end
