require 'test_helper'

class ReviewerAccessTest < ActiveSupport::TestCase
  setup do
    @request = submission_requests(:bioproject)
  end

  test 'mints an unguessable token on create' do
    access = @request.create_reviewer_access!(expires_at: 1.week.from_now)

    assert access.token.present?
    assert_operator access.token.length, :>=, 24
  end

  test 'rejects a past expires_at' do
    access = @request.build_reviewer_access(expires_at: 1.day.ago)

    assert_not access.valid?
    assert_includes access.errors[:expires_at], 'must be in the future'
  end

  test 'active scope excludes expired links' do
    live = @request.create_reviewer_access!(expires_at: 1.day.from_now)
    expired = ReviewerAccess.create!(submission_request: submission_requests(:biosample), expires_at: 1.day.from_now)
    expired.update_column(:expires_at, 1.day.ago) # bypass the create-time future check

    assert_includes     ReviewerAccess.active, live
    assert_not_includes ReviewerAccess.active, expired
  end

  test 'share_url points at the web SPA reviewer route' do
    access = @request.create_reviewer_access!(expires_at: 1.week.from_now)

    assert_match %r{/web/reviews/#{access.token}\z}, access.share_url
  end
end
