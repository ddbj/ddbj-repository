require_relative "../../app/refinements/fetch_raise_error"

Retriable.configure do |config|
  config.contexts[:fetch] = {
    on: [
      Errno::ECONNREFUSED,
      FetchRaiseError::ServerError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Net::WriteTimeout,
      Socket::ResolutionError
    ],

    tries:         Rails.env.test? ? 1 : 10,
    base_interval: 1,
    multiplier:    2
  }
end
