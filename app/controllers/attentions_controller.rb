# What the submitter must not miss, independent of which screen they are
# on.
#
# An unread-message badge on a list row is only visible if the request
# happens to be on the page you are looking at — page 2 of a long list
# hides it completely. The web client polls this once per navigation and
# renders a global band, matching the wording of the notification email so
# the two do not describe the same thing differently.
class AttentionsController < ApplicationController
  def show
    @requests = current_user
      .submission_requests
      .where(id: SubmissionMessage.curator_role.unread.select(:submission_request_id))
      .includes(:submission)
      .order(id: :desc)
  end
end
