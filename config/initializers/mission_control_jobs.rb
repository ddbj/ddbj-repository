Rails.application.config.to_prepare do
  MissionControl::Jobs::ApplicationController.class_eval do
    skip_before_action :authenticate!
  end
end
