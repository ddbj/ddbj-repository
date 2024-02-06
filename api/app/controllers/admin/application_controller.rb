class Admin::ApplicationController < ApplicationController
  before_action :authenticate_admin

  private

  def authenticate_admin
    render json: {
      error: 'Forbidden'
    }, status: :forbidden unless current_user.admin?
  end
end
