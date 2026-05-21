module Admin
  class UsersController < ApplicationController
    before_action :load_user_detail, only: %i[show update]

    def index
      @include_inactive = ActiveModel::Type::Boolean.new.cast(params[:include_inactive])

      scope = User.order(:uid)
      scope = scope.with_submission_requests unless @include_inactive

      @users = scope.limit(100).to_a

      uids = @users.map(&:uid)

      profiles = if params[:query].present?
        registered = uids.to_set
        CloakmanClient.new.search(params[:query]).select { registered.include?(it['uid']) }
      else
        CloakmanClient.new.lookup(uids)
      end

      @profiles_by_uid = profiles.index_by { it['uid'] }
      @counts          = activity_counts(@users.map(&:id))
    end

    def show; end

    def update
      @user.update!(params.expect(user: [:notes]))

      redirect_to admin_user_path(uid: @user.uid), notice: 'Notes saved.', status: :see_other
    end

    private

    def load_user_detail
      @user    = User.find_by!(uid: params[:uid])
      @profile = CloakmanClient.new.lookup([@user.uid]).first or raise ActiveRecord::RecordNotFound

      @counts = activity_counts([@user.id])
    end

    def activity_counts(user_ids)
      rows = SubmissionRequest
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck(:user_id, Arel.sql('COUNT(*)'), Arel.sql('COUNT(submission_id)'))

      requests    = Hash.new(0)
      submissions = Hash.new(0)

      rows.each do |user_id, request_count, submission_count|
        requests[user_id]    = request_count
        submissions[user_id] = submission_count
      end

      {requests:, submissions:}
    end
  end
end
