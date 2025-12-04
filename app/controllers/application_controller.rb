class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Pagy::Method

  before_action :authenticate!

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = authenticate_with_http_token {|token|
      next nil unless user = token.count('.') == 2 ? find_user_from_jwt(token) : find_user_from_api_key(token)

      if user.admin? && uid = request.headers['X-Dway-User-Id']
        User.find_by(uid:)
      else
        user
      end
    }
  end

  private

  def authenticate!
    return if current_user

    render json: {
      error: 'Unauthorized'
    }, status: :unauthorized
  end

  def find_user_from_jwt(token)
    Rails.error.handle(JWT::DecodeError) {
      payload, = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS512')

      User.find_by(id: payload.fetch('user_id'))
    }
  end

  def find_user_from_api_key(token)
    User.find_by(api_key: token)
  end
end
