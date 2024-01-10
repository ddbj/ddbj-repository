class Requests::FilesController < ApplicationController
  include FileDownload

  def show
    request = current_user.requests.find(params[:request_id])

    redirect_to find_file(request.objs).url, allow_other_host: true
  end
end
