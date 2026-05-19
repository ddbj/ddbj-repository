module Admin
  class UsersController < ApplicationController
    def index
      scope = User.order(:uid)
      scope = scope.with_submission_requests unless params[:include_inactive] == '1'

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
