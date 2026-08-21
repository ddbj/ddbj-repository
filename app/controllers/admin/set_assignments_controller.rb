module Admin
  # Who is answering a set's conversation.
  #
  # The set-axis twin of Admin::AssignmentsController, plus the release a
  # request gets from the assignee field in its curation rail — a set has
  # no such rail, so both live here: `create` claims it (for yourself, or
  # for a colleague you are handing it to) and `destroy` puts it back.
  class SetAssignmentsController < ApplicationController
    before_action :load_set

    def create
      @set.assign! assignee

      redirect_to admin_set_path(@set), notice: "Answering: #{@set.assignee.uid}."
    rescue ArgumentError => e
      redirect_to admin_set_path(@set), alert: "Could not assign: #{e.message}"
    end

    def destroy
      @set.assign! nil

      redirect_to admin_set_path(@set), notice: 'Released. Nobody is answering this set.'
    end

    private

    # Absent means "me", which is what the one-click claim on the queue
    # sends. A named one is a hand-over, and it has to be a curator.
    def assignee
      id = params[:assignee_id].presence or return current_user

      User.staff.find(id)
    end

    def load_set = @set = SubmissionSet.find(params.expect(:set_id))
  end
end
