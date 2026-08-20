# Direct upload for the curator screens — the message composer attaches
# files this way. Same reasoning as the API's: see DirectUploadsController.
class Admin::DirectUploadsController < ActiveStorage::DirectUploadsController
  include AdminAuthentication

  before_action :authenticate_admin!
end
