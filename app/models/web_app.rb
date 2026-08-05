# Builds links into the Ember SPA. The app is served under /web on the web
# origin (`rootURL` in web/config/environment.js), so every outgoing link —
# mails, reviewer share URLs, post-login redirects — goes through here rather
# than spelling the prefix out again and getting it wrong.
module WebApp
  # The SPA route that exchanges a freshly minted token for a session.
  #
  # A contract with `web/app/router.ts` that nothing else enforces: the
  # client owns the path, Rails owns the redirect that lands on it, and the
  # two live in different languages. Named here so the redirects cannot at
  # least drift from each other; a test asserts it still matches the router.
  AUTH_CALLBACK_PATH = '/auth/callback'.freeze

  module_function

  def url_for(path = '/')
    URI.join(Rails.application.config_for(:app).web_url!, File.join('/web', path)).to_s
  end
end
