class ApplicationController < ActionController::API
  include TokenAuthentication
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

  private

  def forbid!(message)
    raise Forbidden, message
  end

  def refuse!(message)
    raise UnprocessableContent, message
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
end
