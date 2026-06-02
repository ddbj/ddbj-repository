class SubmissionUpdate < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  enum :source, {
    migration: 0,
    manual:    1,
    batch:     2
  }, validate: true

  belongs_to :submission, inverse_of: :updates

  validates :patch, length: {minimum: 1}
end
