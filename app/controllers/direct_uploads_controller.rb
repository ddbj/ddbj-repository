# Direct upload, authenticated.
#
# Active Storage's own endpoint is publicly reachable by design — it only
# mints a blob row and a presigned PUT, and the signed id it hands back
# is worthless until something attaches it. That was survivable while it
# was Rails' route on Rails' terms; it is not something to redraw
# unauthenticated. Anybody could fill the bucket.
#
# Inherits Active Storage's controller rather than reimplementing it: the
# body it returns is a contract with @rails/activestorage in the browser.
# It descends from ActionController::Base, which is why the token
# authentication lives in a concern rather than in ApplicationController.
class DirectUploadsController < ActiveStorage::DirectUploadsController
  include TokenAuthentication

  before_action :authenticate!
end
