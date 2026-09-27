class DRASubmission < ApplicationRecord
  include Lifecycleable

  # SRA for the 27 early submissions D-way numbers under that prefix.
  ACCESSION_FORMAT = /\A[DS]RA\d{6,}\z/

  belongs_to :submission

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true

  # None: the status is D-way's until DRA is curated here, and the next
  # import would put back a status set in the repository.
  def self.settable_statuses = []
end
