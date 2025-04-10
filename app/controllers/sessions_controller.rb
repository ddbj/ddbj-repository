class SessionsController < ApplicationController
  skip_before_action :authenticate!, only: %i[create]

  def create
    uid  = request.env.dig("omniauth.auth", "extra", "raw_info", "preferred_username")
    user = User.find_or_initialize_by(uid:)

    user.update! admin: request.env.dig("omniauth.auth", "extra", "raw_info", "account_type_number") == 3

    url       = URI.join(Rails.application.config_for(:app).web_url!, "/web/login")
    url.query = URI.encode_www_form(token: user.token)

    redirect_to url.to_s, allow_other_host: true
  end
end
