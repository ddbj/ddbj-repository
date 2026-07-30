class SessionsController < ApplicationController
  ADMIN_ACCOUNT_TYPE = 3

  skip_before_action :authenticate!, only: %i[create]

  def create
    auth = request.env['omniauth.auth']
    uid  = auth.dig('extra', 'raw_info', 'preferred_username')
    user = User.find_or_initialize_by(uid:)

    # The `email` scope is requested (config/initializers/omniauth.rb), so
    # every login refreshes our copy of the address. Keep the existing one
    # if this token carries none rather than blanking a known address.
    user.update!(
      admin: auth.dig('extra', 'raw_info', 'account_type_number') == ADMIN_ACCOUNT_TYPE,
      email: auth.dig('info', 'email').presence || user.email
    )

    origin = request.env['omniauth.origin']

    if origin == '/admin' || origin&.start_with?('/admin/')
      # Admin uses a Rails session cookie; the web client is JWT-only. Only
      # mint the cookie for the admin flow so the two logins stay
      # independent (a web login must not silently grant an admin session,
      # and vice versa).
      session[:user_id] = user.id
      redirect_to origin
    else
      redirect_to_web '/login', token: user.token
    end
  end
end
