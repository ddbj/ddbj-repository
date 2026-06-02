class Project < ApplicationRecord
  include Lifecycleable
  include AdminAssignable

  ACCESSION_FORMAT = /\APRJD[B-Z]\d+\z/

  enum :project_type, {
    primary:  0,
    umbrella: 1
  }, validate: true

  belongs_to :submission

  has_many :parent_links, class_name: 'ProjectLink', foreign_key: :child_project_id,  inverse_of: :child_project,  dependent: :destroy
  has_many :child_links,  class_name: 'ProjectLink', foreign_key: :parent_project_id, inverse_of: :parent_project, dependent: :destroy

  has_many :parents,  through: :parent_links, source: :parent_project
  has_many :children, through: :child_links,  source: :child_project

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true
end
