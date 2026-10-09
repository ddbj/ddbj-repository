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
end
