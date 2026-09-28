class Sample < ApplicationRecord
  include Lifecycleable

  ACCESSION_FORMAT = /\ASAMD\d+\z/

  enum :release_type, {
    release: 1,
    hold:    2
  }, validate: {allow_nil: true}

  belongs_to :submission

  has_many :sample_references, dependent: :destroy

  validates :sample_name, presence: true
  validates :accession,   format: {with: ACCESSION_FORMAT}, allow_nil: true

  # The columns that project a sample of the record (as the record stores
  # it) — what the lists and the admin screens read without opening it.
  def self.record_columns(sample)
    {
      accession:   sample['accession'],
      sample_name: sample['alias'],
      title:       sample['title'],
      package:     sample['package'],
      taxonomy_id: DDBJRecord.taxonomy_id_number(sample.dig('organism', 'taxonomy_id')),
      organism:    sample.dig('organism', 'name')
    }
  end

  # `sample_name` is the sample's `alias` in the record, spelled as the
  # record stores it — which is what the TSV import, accession issuance and
  # the public XML find its record by. A name spelled otherwise (D-way's
  # runs of spaces, a TSV cell from Excel with NBSP) is compared in this
  # form: the string class of `/samples/*/alias` (canonical-json.md §2.2).
  # A name the class rejects is compared as it is.
  def self.normalise_name(name)
    return name if name.nil?

    DDBJRecord::Canonicalizer::StringNormalizer.normalize(name, DDBJRecord::Canonicalizer::PathClassifier.string_class('/samples/0/alias'))
  rescue DDBJRecord::Canonicalizer::Error
    name
  end
end
