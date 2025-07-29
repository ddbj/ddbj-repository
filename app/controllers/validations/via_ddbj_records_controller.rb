class Validations::ViaDDBJRecordsController < ApplicationController
  def create
    @validation = current_user.validations.create!(db: params[:db], progress: :finished, finished_at: Time.current) { |validation|
      validation.objs.build _id: "_base",       validity: "valid"
      validation.objs.build _id: "DDBJ Record", validity: "valid", file: params["DDBJ Record"]["file"]
    }

    render status: :created
  end
end
