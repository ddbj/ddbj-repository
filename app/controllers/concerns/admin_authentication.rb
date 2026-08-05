module AdminAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_admin!
    return redirect_to(new_admin_session_path(origin: request.original_fullpath)) unless current_user
    return if current_user.admin?

    # Not a login failure — logging in again reaches the same result, so
    # the page says so and points at the submitter view instead of at the
    # login button. A bare 403 left the person with no way out at all.
    render 'admin/sessions/forbidden', status: :forbidden, layout: 'auth'
  end
end
