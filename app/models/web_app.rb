# Builds links into the Ember SPA. The app is served under /web on the web
# origin (`rootURL` in web/config/environment.js), so every outgoing link —
# mails, reviewer share URLs, post-login redirects — goes through here rather
# than spelling the prefix out again and getting it wrong.
module WebApp
  module_function

  def url_for(path = '/')
    URI.join(Rails.application.config_for(:app).web_url!, File.join('/web', path)).to_s
  end
end
