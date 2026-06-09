class SessionsController < ApplicationController
  ADMIN_ACCOUNT_TYPE = 3

  skip_before_action :authenticate!, only: %i[create destroy]

  def create
    uid  = request.env.dig('omniauth.auth', 'extra', 'raw_info', 'preferred_username')
    user = User.find_or_initialize_by(uid:)

    user.update! admin: request.env.dig('omniauth.auth', 'extra', 'raw_info', 'account_type_number') == ADMIN_ACCOUNT_TYPE

    session[:user_id] = user.id

    origin = request.env['omniauth.origin']

    if origin == '/admin' || origin&.start_with?('/admin/')
      redirect_to origin
    else
      redirect_to_web '/web/login', token: user.token
    end
  end

  def destroy
    reset_session

    redirect_to_web
  end
end
