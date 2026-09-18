# The caller's files: uploaded, verified, and waiting to be named in a
# submission. See User#files.
class FilesController < ApplicationController
  # Taking a file away is the account holder's. A curator acting for somebody
  # can see what they have uploaded, and upload for them, but not discard it.
  before_action :refuse_proxy!, only: %i[destroy]

  # Newest first: the file somebody is looking for is usually the one they
  # have just uploaded.
  def index
    @files = paginate(current_user.files_attachments.includes(:blob).order(created_at: :desc, id: :desc))
  end

  # Detaches, and nothing more. The file's bytes go once nothing else refers to
  # them, which is PurgeUnattachedUploadsJob's to decide — anything else that
  # holds the same blob keeps it.
  def destroy
    current_user.files_attachments.find(params.expect(:id)).destroy!

    head :no_content
  end
end
