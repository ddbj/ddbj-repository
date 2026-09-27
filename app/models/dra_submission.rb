class DRASubmission < ApplicationRecord
  include Lifecycleable

  ACCESSION_FORMAT = /\ADRA\d{6,}\z/

  belongs_to :submission

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true
end
