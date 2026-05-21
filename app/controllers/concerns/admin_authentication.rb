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
    return redirect_to('/auth/keycloak', allow_other_host: true) unless current_user

    head :forbidden unless current_user.admin?
  end
end
