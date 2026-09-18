# The caller's unassigned files: uploaded, verified, and waiting to be assigned
# to a submission. A file leaves the list once something is assigned it
# (ReleaseAssignedFilesJob). See User#unassigned_files.
class UnassignedFilesController < ApplicationController
  # Taking a file away is the account holder's. A curator acting for somebody
  # can see what they have uploaded, and upload for them, but not discard it.
  before_action :refuse_proxy!, only: %i[destroy]

  # Newest first: the file somebody is looking for is usually the one they
  # have just uploaded.
  def index
    @files = paginate(current_user.unassigned_files_attachments.includes(:blob).order(created_at: :desc, id: :desc))
  end

  # Detaches, and nothing more. The file's bytes go once nothing refers to them,
  # which is PurgeUnattachedUploadsJob's to decide — anything else holding the
  # same blob keeps it.
  def destroy
    current_user.unassigned_files_attachments.find(params.expect(:id)).destroy!

    head :no_content
  end
end
