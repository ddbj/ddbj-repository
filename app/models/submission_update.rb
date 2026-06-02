class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  enum :source, {
    manual:    0,
    migration: 1,
    batch:     2
  }, validate: true

  belongs_to :submission, inverse_of: :updates

  validates :patch, length: {minimum: 1, maximum: 16.megabytes}

  # Memoised parse of the bytea-stored JSON Patch. Returns the RFC 6902
  # operation array.
  def parsed_patch
    @parsed_patch ||= Oj.load(patch, mode: :strict)
  end

  def op_count
    parsed_patch.length
  end
end
