class Sample < ApplicationRecord
  include Lifecycleable

  ACCESSION_FORMAT = /\ASAMD\d+\z/

  enum :release_type, {
    release: 1,
    hold:    2
  }, validate: {allow_nil: true}

  belongs_to :submission
  belongs_to :assignee, class_name: 'User', optional: true

  has_many :sample_references, dependent: :destroy

  validates :sample_name, presence: true
  validates :accession,   format: {with: ACCESSION_FORMAT}, allow_nil: true
  validate  :assignee_must_be_admin

  private

  def assignee_must_be_admin
    return if assignee.nil? || assignee.admin?

    errors.add(:assignee, 'must be an admin user')
  end
end
