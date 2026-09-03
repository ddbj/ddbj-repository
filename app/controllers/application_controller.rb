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

  # Past the end of any list this application can hold, and well short of
  # what Postgres refuses. A page number is multiplied into an OFFSET, so
  # without a ceiling `?page=99999999999999999999` is not an empty page
  # but a bigint overflow — a 500, and on the reviewer's routes one that
  # anybody holding a share link can produce.
  MAX_PAGE = 1_000_000

  # A page of a list, and the headers that say where in the list it is.
  #
  # The two belong together: a client that is not told `Total-Pages` reads
  # a truncated list as the whole of one, which is the failure a paginated
  # endpoint has instead of an error. Written once because there is no
  # request where one half is wanted without the other.
  def paginate(scope)
    pagy, records = pagy(scope, page: params[:page].to_i.clamp(1, MAX_PAGE))

    response.headers.merge! pagy.headers_hash

    records
  end

  def forbid!(message)
    raise Forbidden, message
  end

  def refuse!(message)
    raise UnprocessableContent, message
  end

  # Acting as somebody else is for helping them with what they submitted.
  # It does not extend to deciding who they collaborate with, or to
  # speaking in their name: a set membership, an invitation and a message
  # all record who did it, and under a proxy that record would name the
  # person being helped rather than the curator doing the helping.
  # Reading is untouched.
  def refuse_proxy!
    return unless proxying?

    forbid! 'A set cannot be written to while acting as another account.'
  end
end
