require 'test_helper'

class WebAppTest < ActiveSupport::TestCase
  test 'url_for prefixes the SPA mount point' do
    assert_equal 'http://repository.example.com:4200/web/requests/42', WebApp.url_for('/requests/42')
  end

  test 'url_for defaults to the SPA root' do
    assert_equal 'http://repository.example.com:4200/web/', WebApp.url_for
  end

  # The one contract in this codebase that crosses a language boundary with
  # nothing enforcing it: Rails redirects a freshly minted token at a path
  # that the Ember router owns. Renaming the route on one side leaves the
  # other pointing at a page that ignores the token — the person logs in,
  # is returned to the sign-in screen, and every test still passes because
  # each side is self-consistent.
  #
  # Reading the router is crude, but it is the only place the two meet.
  test 'the token-callback path is a route the SPA actually has' do
    router = Rails.root.join('web/app/router.ts').read
    path   = WebApp::AUTH_CALLBACK_PATH.delete_prefix('/')

    assert_match(/path:\s*'#{Regexp.escape(path)}'/, router,
                 "web/app/router.ts must declare a route at #{path.inspect} — " \
                 'a login lands there carrying the token')
  end
end
