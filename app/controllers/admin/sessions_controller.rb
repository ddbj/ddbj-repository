module Admin
  class SessionsController < ApplicationController
    skip_before_action :authenticate_admin!

    def new
      @origin = params[:origin].presence || admin_root_path
    end
  end
end
