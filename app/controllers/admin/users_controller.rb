module Admin
  class UsersController < ApplicationController
    def index
      include_inactive = ActiveModel::Type::Boolean.new.cast(params[:include_inactive])

      scope = User.order(:uid)
      scope = scope.with_submission_requests unless include_inactive

      @users = scope.to_a

      uids = @users.map(&:uid)

      @profiles = if query = params[:query].presence
        registered = uids.to_set
        CloakmanClient.new.search(query).select { registered.include?(it['uid']) }
      else
        CloakmanClient.new.lookup(uids)
      end

      @counts = activity_counts(@users.map(&:id))
    end

    def show
      @user    = User.find_by!(uid: params[:uid])
      @profile = CloakmanClient.new.lookup([@user.uid]).first or raise ActiveRecord::RecordNotFound

      @counts = activity_counts([@user.id])
    end

    def update
      user = User.find_by!(uid: params[:uid])
      user.update!(params.expect(user: [:notes]))

      head :no_content
    end

    private

    def activity_counts(user_ids)
      scope = SubmissionRequest.where(user_id: user_ids)

      {
        requests:    scope.group(:user_id).count,
        submissions: scope.where.not(submission_id: nil).group(:user_id).count
      }
    end
  end
end
