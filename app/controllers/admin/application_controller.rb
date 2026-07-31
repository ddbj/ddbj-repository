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

    # Record that the current curator has worked on a request, as a side
    # effect of whatever they came here to do. Called from the success
    # path of each mutating action rather than from a blanket
    # `after_action`: a refused save is not work, a bulk action touches
    # many requests at once, and which request an action addresses is not
    # something a generic hook can infer without guessing.
    #
    # See SubmissionRequestParticipant — this grants nothing and moves no
    # assignment, so it is safe to call anywhere it is true.
    def participate!(request)
      request&.participate!(current_user)
    end

    # Nav badge counts. Rendered on every admin page, so both are single
    # aggregate queries with no eager loading, memoised for the request.
    def needs_action_count
      @needs_action_count ||= CurationQueue.count
    end

    def my_queue_count
      @my_queue_count ||= SubmissionRequest.assigned_to(current_user).count
    end
  end
end
