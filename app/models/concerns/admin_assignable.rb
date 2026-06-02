module AdminAssignable
  extend ActiveSupport::Concern

  included do
    belongs_to :assignee, class_name: 'User', optional: true

    validate :assignee_must_be_admin
  end

  private

  def assignee_must_be_admin
    return if assignee.nil? || assignee.admin?

    errors.add(:assignee, 'must be an admin user')
  end
end
