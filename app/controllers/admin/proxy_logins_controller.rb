module Admin
  class ProxyLoginsController < ApplicationController
    def create
      User.find_by!(uid: params[:user_uid])

      redirect_to_web '/web/', proxy_login: params[:user_uid]
    end
  end
end
