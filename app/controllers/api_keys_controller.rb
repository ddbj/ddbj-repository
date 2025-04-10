class ApiKeysController < ApplicationController
  def regenerate
    current_user.update! api_key: User.generate_api_key

    render json: {
      api_key: current_user.api_key
    }
  end
end
