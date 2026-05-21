class SessionsController < ApplicationController
  ADMIN_ACCOUNT_TYPE = 3

  skip_before_action :authenticate!, only: %i[create destroy]

  def create
    uid  = request.env.dig('omniauth.auth', 'extra', 'raw_info', 'preferred_username')
    user = User.find_or_initialize_by(uid:)

    user.update! admin: request.env.dig('omniauth.auth', 'extra', 'raw_info', 'account_type_number') == ADMIN_ACCOUNT_TYPE

    session[:user_id] = user.id

    redirect_to_web '/web/login', token: user.token
  end

  def destroy
    reset_session

    redirect_to_web
  end
end
