module Admin
  # Naming the filter you are looking at, and taking the name away again.
  #
  # Both land back on the ledger showing the same rows as before: saving
  # is not a navigation, and a curator who names their view and then finds
  # themselves somewhere else has to filter again to check it took.
  class SavedViewsController < ApplicationController
    def create
      name = params[:name].to_s.strip
      view = current_user.saved_views.new(name:, filters: RequestFilter.normalise(params))

      if view.save
        redirect_to ledger_path, notice: "Saved “#{view.name}”."
      else
        refuse view, name
      end
    # Two presses of Save race past a uniqueness validation that reads
    # before it writes, and the index is what actually settles it. The
    # loser is the same refusal as any other duplicate, not a 500.
    rescue ActiveRecord::RecordNotUnique
      refuse view, name, 'Name has already been taken.'
    end

    # Scoped to the current curator's own views, so an id from somebody
    # else's row is a 404 rather than a deletion.
    def destroy
      view = current_user.saved_views.find(params[:id])
      view.destroy!

      redirect_to ledger_path, notice: "Deleted “#{view.name}”."
    end

    private

    # Back to the ledger with the name still typed and the form still
    # open. A redirect that dropped both left the curator reading "Name
    # has already been taken" with no form on screen and nothing to
    # correct — they had to find Save this view, reopen it and type it
    # again.
    def refuse(view, name, message = nil)
      redirect_to ledger_path(view_name: name),
                  alert: message || view.errors.full_messages.to_sentence
    end

    # The rows that were on screen, including which page of them. The
    # filters ride in the request rather than being read off the saved
    # view — on delete there is no view left to read, and on save the two
    # are the same thing.
    #
    # `page` is not part of a view (a view is a set of rows, not a
    # position in it) but it is part of where the curator was standing,
    # which is what this is for.
    def ledger_path(extra = {})
      admin_submission_requests_path(
        RequestFilter.normalise(params).merge(extra).compact.merge(page: params[:page].presence).compact
      )
    end
  end
end
