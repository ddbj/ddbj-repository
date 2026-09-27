class DRASubmission < ApplicationRecord
  include Lifecycleable

  # SRA for the 27 early submissions D-way numbers under that prefix.
  ACCESSION_FORMAT = /\A[DS]RA\d{6,}\z/

  belongs_to :submission

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true
end
