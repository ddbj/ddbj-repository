Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    skip_forgery_protection
  end
end
