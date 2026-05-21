MissionControl::Jobs.http_basic_auth_enabled = false

Rails.application.config.to_prepare do
  MissionControl::Jobs::ApplicationController.class_eval do
    skip_before_action :authenticate!

    include AdminAuthentication

    before_action :authenticate_admin!
  end
end
