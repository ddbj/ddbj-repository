module Admin
  class UsersController < ApplicationController
    def index
      @users = CloakmanClient.new.users(query: params[:query].presence)
    end
  end
end
