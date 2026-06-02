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
end
