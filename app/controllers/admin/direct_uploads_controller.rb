# Direct upload for the curator screens — the message composer attaches
# files this way. Same reasoning as the API's: see DirectUploadsController.
class Admin::DirectUploadsController < ActiveStorage::DirectUploadsController
  include AdminAuthentication

  # Active Storage turns forgery protection off on its own controller,
  # which is right for the endpoint it drew: public, and authenticated by
  # nothing. This one is authenticated by a session cookie, and a cookie
  # is sent whoever asked for the request — so a form on another site
  # would create blob rows as whichever curator has this open.
  protect_from_forgery with: :exception

  before_action :authenticate_admin!

  private

  # `authenticate_admin!` answers a browser with the sign-in page, which
  # is right for a navigation and wrong for this: the uploader would
  # follow the redirect, get 200 and a page of HTML, and fall over
  # destructuring a body that is not there. A curator whose session
  # lapsed mid-message would see nothing happen at all.
  def authenticate_admin!
    return super unless request.xhr? || request.format.json?
    return if current_user&.admin?

    head :unauthorized
  end
end
