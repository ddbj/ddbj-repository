module Admin
  class UsersController < ApplicationController
    def index
      client = CloakmanClient.new

      @users = if query = params[:query].presence
        users           = client.users(query:)
        registered_uids = User.where(uid: users.map { it['uid'] }).pluck(:uid).to_set

        users.select { registered_uids.include?(it['uid']) }
      else
        client.users(uids: User.order(:uid).pluck(:uid))
      end
    end
  end
end
