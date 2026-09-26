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

  # The typed column's value for the record's taxonomy_id, which v3 keeps as
  # written ("009606", "not applicable"): the number it names, or nil.
  def self.taxonomy_id_of(value) = Integer(value.to_s.strip, 10, exception: false)
end
