module Admin
  class ProxyLoginsController < ApplicationController
    def create
      User.find_by!(uid: params[:user_uid])

      # The web client is JWT-only, so hand it the admin's own token (this
      # action is session-authenticated) alongside the proxy target. It
      # logs in with that token and then acts as `user_uid` via the
      # X-Dway-User-Id header — no separate web login required.
      redirect_to_web '/web/login', token: current_user.token, proxy_login: params[:user_uid]
    end
  end
end
