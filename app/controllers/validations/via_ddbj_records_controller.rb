class Validations::ViaDDBJRecordsController < ApplicationController
  def create
    @validation = current_user.validations.create!(
      db:          params[:db],
      via:         :ddbj_record,
      progress:    :finished,
      finished_at: Time.current
    ) {|validation|
      validation.objs.build _id: '_base',      validity: 'valid'
      validation.objs.build _id: 'DDBJRecord', validity: 'valid', file: params['DDBJRecord']['file']
    }

    render status: :created
  end
end
