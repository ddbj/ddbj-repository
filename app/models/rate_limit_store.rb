# Where the rate limiters count, resolved when a request arrives rather
# than when the class is loaded.
#
# `rate_limit store:` defaults to the controller's cache store and holds
# whatever was configured at boot. In test that is the null store, whose
# `increment` returns nil — and the limiter reads nil as "not over the
# limit", so every limit in the app is a no-op no test can see. A limit
# nothing exercises is a limit nobody knows the shape of, which for the
# unauthenticated reader below is the whole point of having one.
#
# Delegating leaves production behaviour exactly as it was and lets a test
# put a real store in front of it.
module RateLimitStore
  def self.increment(...) = Rails.cache.increment(...)
end
