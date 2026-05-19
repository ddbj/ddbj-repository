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
  end
end
