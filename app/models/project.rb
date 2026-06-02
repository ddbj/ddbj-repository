class Project < ApplicationRecord
  include Lifecycleable

  ACCESSION_FORMAT = /\APRJD[B-Z]\d+\z/

  enum :project_type, {
    primary:  0,
    umbrella: 1
  }, validate: true

  belongs_to :submission
  belongs_to :assignee, class_name: 'User', optional: true

  has_one  :parent_link, class_name: 'ProjectLink', foreign_key: :child_project_id,  inverse_of: :child_project,  dependent: :destroy
  has_many :child_links, class_name: 'ProjectLink', foreign_key: :parent_project_id, inverse_of: :parent_project, dependent: :destroy

  has_one  :parent,   through: :parent_link, source: :parent_project
  has_many :children, through: :child_links, source: :child_project

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true
  validate  :assignee_must_be_admin

  private

  def assignee_must_be_admin
    return if assignee.nil? || assignee.admin?

    errors.add(:assignee, 'must be an admin user')
  end
end
