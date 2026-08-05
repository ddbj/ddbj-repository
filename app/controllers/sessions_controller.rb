class SessionsController < ApplicationController
  skip_before_action :authenticate!, only: %i[create]

  def create
    auth = request.env['omniauth.auth']
    uid  = auth.dig('extra', 'raw_info', 'preferred_username')
    user = User.find_or_initialize_by(uid:)

    # The `email` scope is requested (config/initializers/omniauth.rb), so
    # every login refreshes our copy of the address. Keep the existing one
    # if this token carries none rather than blanking a known address.
    user.update!(
      admin: staff?(auth),
      email: auth.dig('info', 'email').presence || user.email,

      # Separates an account imported from D-way that nobody has ever used
      # from one whose owner was here last week — which is what a curator
      # is asking when they wonder whether an address is worth mailing.
      last_signed_in_at: Time.current
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
      redirect_to_web WebApp::AUTH_CALLBACK_PATH, token: user.token
    end
  end

  private

  # The id token carries `account_type_number` as an integer; the REST
  # profile carries it as a name. CloakmanClient owns that translation so
  # neither shape has to be remembered here.
  def staff?(auth)
    type = auth.dig('extra', 'raw_info', 'account_type_number')

    CloakmanClient.account_type_name(type) == CloakmanClient::STAFF_ACCOUNT_TYPE
  end
end
