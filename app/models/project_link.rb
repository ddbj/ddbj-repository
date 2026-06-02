class ProjectLink < ApplicationRecord
  belongs_to :child_project,  class_name: 'Project', inverse_of: :parent_links
  belongs_to :parent_project, class_name: 'Project', inverse_of: :child_links, optional: true

  validate :exactly_one_target

  private

  def exactly_one_target
    has_parent   = parent_project_id.present?
    has_external = external_accession.present?

    return if has_parent ^ has_external

    errors.add(:base, 'specify exactly one of parent_project or external_accession')
  end
end
