OpenIDConnect.logger = Rails.logger
Rack::OAuth2.logger  = Rails.logger
WebFinger.logger     = Rails.logger
SWD.logger           = Rails.logger

SWD.url_builder = URI::HTTP if ENV['DISABLE_SSL'] == 'true'
