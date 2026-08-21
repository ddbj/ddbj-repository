module Admin
  # Following a set's thread, per curator. The set-axis twin of
  # Admin::SubscriptionsController, and singular for the same reason:
  # what is being created is this curator's relationship to this set,
  # which has no id of its own.
  class SetSubscriptionsController < ApplicationController
    before_action :load_set

    def create
      @set.subscribe! current_user

      redirect_to admin_set_path(@set), notice: 'Following this set.'
    end

    def destroy
      @set.unsubscribe! current_user

      redirect_to admin_set_path(@set), notice: 'No longer following this set.'
    end

    private

    def load_set = @set = SubmissionSet.find(params.expect(:set_id))
  end
end
