class ApiKeysController < ApplicationController
  skip_before_action :authenticate, only: %i(show)

  def show
    render json: {
      login_url: login_auth_url
    }
  end

  def regenerate
    current_user.update! api_key: User.generate_api_key

    render json: {
      api_key: current_user.api_key
    }
  end
end
