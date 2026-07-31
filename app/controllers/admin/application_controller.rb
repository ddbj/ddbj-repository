module Admin
  class ApplicationController < ActionController::Base
    include AdminAuthentication
    include WebRedirect
    include Pagy::Method

    helper Admin::ViewHelpers

    layout 'admin'

    before_action :authenticate_admin!

    helper_method :my_queue_count

    private

    # Who did it, as the audit trail spells it. Every actor string in the
    # admin is this shape, and writing it out at each call site meant a
    # future change of shape would be eight edits and a grep.
    def current_actor = "admin:#{current_user.uid}"

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

    # Nav badge. Rendered on every admin page, so it is three aggregate
    # queries with no eager loading, memoised for the request — the same
    # three the screen itself runs, and the sections are disjoint so they
    # add up without double-counting.
    def my_queue_count
      @my_queue_count ||= MyQueue.new(current_user).count
    end
  end
end
