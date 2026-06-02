class SampleReference < ApplicationRecord
  REF_DBS = %w[
    bioproject
    sra
    dra
    gea
  ].freeze

  REF_ACCESSION_FORMATS = {
    'bioproject' => /\APRJD[B-Z]\d+\z/,
    'sra'        => /\A[DES]R[APRSXZ]\d+\z/,
    'dra'        => /\AD[A-Z]{2}\d+\z/,
    'gea'        => /\AE-GEAD-\d+\z/
  }.freeze

  belongs_to :sample

  validates :ref_db,        presence: true, inclusion: {in: REF_DBS}
  validates :ref_accession, presence: true
  validate  :ref_accession_format

  private

  def ref_accession_format
    fmt = REF_ACCESSION_FORMATS[ref_db]

    return if fmt.nil? || ref_accession =~ fmt

    errors.add(:ref_accession, "is not a valid #{ref_db} accession")
  end
end
