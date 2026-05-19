module Admin
  class UsersController < ApplicationController
    def index
      @users = if query = params[:query].presence
        cloakman_users  = CloakmanClient.new.search(query)
        registered_uids = User.where(uid: cloakman_users.map { it['uid'] }).pluck(:uid).to_set

        cloakman_users.select { registered_uids.include?(it['uid']) }
      else
        CloakmanClient.new.lookup(User.order(:uid).pluck(:uid))
      end
    end

    def show
      @user    = User.find_by!(uid: params[:uid])
      @profile = CloakmanClient.new.lookup([@user.uid]).first or raise ActiveRecord::RecordNotFound
    end
  end
end
