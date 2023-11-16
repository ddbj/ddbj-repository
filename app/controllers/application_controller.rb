class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate

  private

  def authenticate
    render json: {
      error: 'Unauthorized'
    }, status: :unauthorized unless dway_user
  end

  def dway_user
    authenticate_with_http_token {|token|
      DwayUser.find_by(api_token: token)
    }
  end
end
