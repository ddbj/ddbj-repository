module Admin
  # Naming the filter you are looking at, and taking the name away again.
  #
  # Both land back on the ledger showing the same rows as before: saving
  # is not a navigation, and a curator who names their view and then finds
  # themselves somewhere else has to filter again to check it took.
  class SavedViewsController < ApplicationController
    def create
      view = current_user.saved_views.new(
        name:    params[:name].to_s.strip,
        filters: SavedView.normalise(params)
      )

      if view.save
        redirect_to ledger_path, notice: "Saved “#{view.name}”."
      else
        redirect_to ledger_path, alert: view.errors.full_messages.to_sentence
      end
    end

    # Scoped to the current curator's own views, so an id from somebody
    # else's row is a 404 rather than a deletion.
    def destroy
      view = current_user.saved_views.find(params[:id])
      view.destroy!

      redirect_to ledger_path, notice: "Deleted “#{view.name}”."
    end

    private

    # Back to the rows that were on screen. The filters ride in the
    # request rather than being read off the saved view — on delete there
    # is no view left to read, and on save the two are the same thing.
    def ledger_path
      admin_submission_requests_path(SavedView.normalise(params))
    end
  end
end
