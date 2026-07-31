module Admin
  class ApplicationController < ActionController::Base
    include AdminAuthentication
    include WebRedirect
    include Pagy::Method

    helper Admin::ViewHelpers

    layout 'admin'

    before_action :authenticate_admin!

    helper_method :needs_action_count, :my_queue_count

    private

    # Nav badge counts. Rendered on every admin page, so both are single
    # aggregate queries with no eager loading, memoised for the request.
    def needs_action_count
      @needs_action_count ||= CurationQueue.count
    end

    def my_queue_count
      @my_queue_count ||= SubmissionRequest.curated_by(current_user).count
    end
  end
end
