class SampleReference < ApplicationRecord
  REF_DBS = %w[
    bioproject
    sra
    dra
    gea
  ].freeze

  # TODO(open-question): Spike 0.6/curator follow-up will tighten these. The
  # current shapes accept all valid sample-side refs we have seen plus some
  # over-broad cases (e.g. DRA/SRA submission-level vs run-level). Refine when
  # curators confirm which ref_accession kinds actually appear from a sample.
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

    return if fmt.nil? || fmt.match?(ref_accession.to_s)

    errors.add(:ref_accession, "is not a valid #{ref_db} accession")
  end
end
