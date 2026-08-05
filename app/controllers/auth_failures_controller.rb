# Where OmniAuth lands when the provider hands back an error.
#
# The route existed and pointed at `sessions#failure`, which was never
# written — and SessionsController is an API controller behind
# `authenticate!`, so a submitter whose login expired mid-flow got a bare
# `{"error":"Unauthorized"}` JSON body. A failed login is the one moment a
# person is least equipped to interpret that.
#
# Separate from SessionsController because this renders HTML for either
# side of the application, and because the failure path has no session to
# authenticate against by definition.
class AuthFailuresController < ActionController::Base
  layout 'auth'

  # OmniAuth passes `message` (its own symbol, e.g. `invalid_credentials`)
  # and sometimes `origin`. Both are attacker-controllable in the sense
  # that they arrive as query params, so `message` is only ever shown
  # escaped as a code, never interpreted, and `origin` is not turned into
  # a link — the retry goes to the provider, which knows where to return.
  def show
    @message = params[:message].presence
  end
end
