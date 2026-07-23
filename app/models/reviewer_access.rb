class ReviewerAccess < ApplicationRecord
  belongs_to :submission_request

  # Unguessable share token — the reviewer URL is /web/reviews/<token>.
  has_secure_token :token, length: 32

  validates :expires_at, presence: true
  validate  :expires_at_in_future, on: :create

  # Live links only — an expired token must read as "not found" to a
  # reviewer, never as a revoked-but-recognised one.
  scope :active, -> { where(expires_at: Time.current..) }

  def expired?
    expires_at.past?
  end

  # The shareable link the submitter hands to a reviewer. Points at the
  # Ember SPA route (/web/reviews/<token>), not the API.
  def share_url
    URI.join(Rails.application.config_for(:app).web_url!, "/web/reviews/#{token}").to_s
  end

  private

  def expires_at_in_future
    return if expires_at.blank? || expires_at.future?

    errors.add(:expires_at, 'must be in the future')
  end
end
