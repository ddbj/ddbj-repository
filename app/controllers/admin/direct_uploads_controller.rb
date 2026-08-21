# Direct upload for the curator screens — the message composer attaches
# files this way. Same reasoning as the API's: see DirectUploadsController.
class Admin::DirectUploadsController < ActiveStorage::DirectUploadsController
  include AdminAuthentication

  # Before the forgery check, and that order is the point. A session that
  # has lapsed fails that check too — the token it is compared against
  # lives in the session — so a curator whose afternoon ran long would be
  # told 422 by a page of HTML, when what happened is that they need to
  # sign in again.
  before_action :authenticate_admin!

  # Active Storage turns forgery protection off on its own controller,
  # which is right for the endpoint it drew: public, and authenticated by
  # nothing. This one is authenticated by a session cookie, and a cookie
  # is sent whoever asked for the request — so a form on another site
  # would create blob rows as whichever curator has this open.
  protect_from_forgery with: :exception

  private

  # `authenticate_admin!` answers a browser with the sign-in page, which
  # is right for a navigation and wrong for this: the uploader would
  # follow the redirect, get 200 and a page of HTML, and fall over
  # destructuring a body that is not there. A curator whose session
  # lapsed mid-message would see nothing happen at all.
  #
  # Signed in but not a curator is a different answer from not signed in:
  # signing in again reaches the same place, and 401 invites the client
  # to try exactly that.
  def authenticate_admin!
    return super unless request.xhr? || request.format.json?
    return if current_user&.admin?

    head current_user ? :forbidden : :unauthorized
  end
end
