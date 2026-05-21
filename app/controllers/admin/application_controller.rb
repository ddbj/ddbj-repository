module Admin
  class ApplicationController < ActionController::Base
    include AdminAuthentication
    include WebRedirect
    include Pagy::Method

    helper Admin::ViewHelpers

    layout 'admin'

    before_action :authenticate_admin!
  end
end
