module Admin
  # The curator's own workbench: every request whose curation rows are
  # assigned to them. Deliberately a first-class screen rather than a
  # bookmarked `?assignee=<id>` on All requests — it is the default place
  # a curator works from, and the nav badge has to name it.
  class MyQueueController < ApplicationController
    include RequestListing

    def show
      load_requests(SubmissionRequest.assigned_to(current_user).order(id: :desc))
    end
  end
end
