OpenIDConnect.logger = Rails.logger
Rack::OAuth2.logger  = Rails.logger
WebFinger.logger     = Rails.logger
SWD.logger           = Rails.logger

SWD.url_builder = URI::HTTP if URI.parse(ENV.fetch("OIDC_ISSUER_URL")).scheme == "http"
