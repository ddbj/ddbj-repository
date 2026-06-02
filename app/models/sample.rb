class Sample < ApplicationRecord
  include Lifecycleable
  include AdminAssignable

  ACCESSION_FORMAT = /\ASAMD\d+\z/

  enum :release_type, {
    release: 1,
    hold:    2
  }, validate: {allow_nil: true}

  belongs_to :submission

  has_many :sample_references, dependent: :destroy

  validates :sample_name, presence: true
  validates :accession,   format: {with: ACCESSION_FORMAT}, allow_nil: true
end
