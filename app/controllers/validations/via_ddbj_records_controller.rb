class Validations::ViaDDBJRecordsController < ApplicationController
  def create
    @validation = current_user.validations.create!(
      db:          params.expect(:db),
      via:         :ddbj_record,
      progress:    :finished,
      finished_at: Time.current
    ) {|validation|
      validation.objs.build _id: '_base', validity: 'valid'

      destination = record_params[:destination]
      db          = DB.find { it[:id] == params.expect(:db) }

      if file = record_params[:file]
        validation.objs.build(
          _id:         'DDBJRecord',
          validity:    'valid',
          file:,
          destination:
        )
      elsif path = record_params['path']
        obj_schema = db[:objects][:ddbj_record].first

        obj = validation.build_obj_from_path(path, **{
          obj_schema:,
          destination:,
          user:        current_user
        })

        obj.validity = 'valid'
      end
    }

    render status: :created
  end

  private

  def record_params
    params.expect(DDBJRecord: [
      :file,
      :path,
      :destination
    ])
  end
end
