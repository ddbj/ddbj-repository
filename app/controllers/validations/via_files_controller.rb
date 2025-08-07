class Validations::ViaFilesController < ApplicationController
  class UnprocessableContent < StandardError; end

  def create
    @validation = create_validation

    ValidateJob.perform_later @validation

    render status: :created
  end

  private

  def create_validation
    ActiveRecord::Base.transaction {
      unless db = DB.find { it[:id] == params.expect(:db) }
        raise UnprocessableContent, "unknown db: #{params[:db]}"
      end

      validation = current_user.validations.create!(
        db:  db[:id],
        via: :file
      )

      validation.objs.create! _id: '_base'

      db[:objects][:file].each do |obj_schema|
        obj_schema => {id:}
        val = obj_schema[:required] ? params.require(id) : params[id]

        handle_param validation, obj_schema, val
      end

      validation
    }
  end

  def handle_param(validation, obj_schema, val)
    obj_schema => {id:}

    case val
    in ActionController::Parameters
      handle_param validation, obj_schema, val.permit(:file, :path, :destination).to_hash.symbolize_keys
    in {file:, **rest}
      validation.objs.create! _id: id, file: file, **rest.slice(:destination)
    in {path:, **rest}
      validation.build_obj_from_path(path, **{
        obj_schema:,
        destination: rest[:destination],
        user:        current_user
      })

      validation.save!
    in Array if obj_schema[:multiple]
      val.each do |v|
        handle_param validation, obj_schema, v
      end
    in nil unless obj_schema[:required]
      # do nothing
    in unknown
      raise UnprocessableContent, "unexpected parameter format in #{id}: #{unknown.inspect}"
    end
  end
end
