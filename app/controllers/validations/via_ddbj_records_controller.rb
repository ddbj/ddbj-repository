class Validations::ViaDDBJRecordsController < ApplicationController
  def create
    @validation = current_user.validations.create!(db: params[:db], progress: :finished, finished_at: Time.current)
    @validation.objs.create! file: params["DDBJ Record"]["file"], _id: "DDBJ Record", validity: "valid"

    render status: :created
  end
end
