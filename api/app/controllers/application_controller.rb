class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = authenticate_with_http_token { |token|
      next nil unless user = User.find_by(api_key: token)

      if user.admin? && uid = request.headers["X-Dway-User-Id"]
        User.find_by(uid:)
      else
        user
      end
    }
  end

  private

  def authenticate
    render json: {
      error: "Unauthorized"
    }, status: :unauthorized unless current_user
  end
end
