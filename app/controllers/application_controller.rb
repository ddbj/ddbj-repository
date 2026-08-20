class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Pagy::Method
  include WebRedirect

  # Refusing something the caller can see. Where the caller cannot see it
  # the answer is still a 404 — scoping the lookup, as
  # SubmissionRequestsController does — so this is only for the case
  # where hiding the thing would be the confusing answer: you are in this
  # set, you just are not the one who may rename it.
  class Forbidden < StandardError
    include PublicError
  end

  # The request is understood and refused on its own terms. Not a
  # validation failure on a record, so it has nowhere else to come from.
  class UnprocessableContent < StandardError
    include PublicError
  end

  before_action :authenticate!

  # Views render without a `current_user` helper — ActionController::API
  # carries no helper machinery — and some of them have to say what the
  # caller may do rather than leave the client to re-derive the rule. Nil
  # on the unauthenticated endpoints, which is what they mean.
  before_action { @viewer = current_user }

  # A curator is acting as this submitter. Asked by the writes that
  # record who did them — see `refuse_proxy!`. Reading it forces the
  # authentication it describes, so it is never stale.
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

  def forbid!(message)
    raise Forbidden, message
  end

  # Acting as somebody else is for helping them with what they submitted.
  # It does not extend to deciding who they collaborate with: a set
  # membership and an invitation both record who did it, and under a
  # proxy that record would name the person being helped rather than the
  # curator doing the helping. Reading is untouched.
  def refuse_proxy!
    return unless proxying?

    forbid! 'Sets cannot be changed while acting as another account.'
  end

  def refuse!(message)
    raise UnprocessableContent, message
  end

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
