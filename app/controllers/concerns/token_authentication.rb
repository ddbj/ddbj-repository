# Who is calling, for the JSON API and for anything else that has to
# answer the same question.
#
# Extracted from ApplicationController because the direct-upload endpoint
# cannot inherit from it — it is an ActiveStorage controller, and those
# descend from ActionController::Base — but must authenticate the same
# way. Two copies of "how do we know who this is" is not a thing to have.
module TokenAuthentication
  extend ActiveSupport::Concern

  included do
    include ActionController::HttpAuthentication::Token::ControllerMethods
  end

  # A curator is acting as this submitter. Asked by the writes that record
  # who did them — see ApplicationController#refuse_proxy!. Reading it
  # forces the authentication it describes, so it is never stale.
  def proxying?
    current_user && @proxying == true
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = authenticate_with_http_token {|token|
      next nil unless user = token.count('.') == 2 ? find_user_from_jwt(token) : find_user_from_api_key(token)

      if user.admin? && uid = request.headers['X-Dway-User-Id']
        @proxying = true

        User.find_by(uid:)
      else
        user
      end
    }
  end

  private

  def authenticate!
    return if current_user

    render json: {error: 'Unauthorized'}, status: :unauthorized
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
