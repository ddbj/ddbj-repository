using PathnameContain

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
      unless db = DB.find { _1[:id] == params.require(:db) }
        raise UnprocessableContent, "unknown db: #{params[:db]}"
      end

      validation = current_user.validations.create!(db: db[:id])

      validation.objs.create! _id: '_base'

      db[:objects].each do |obj|
        obj => {id:}
        val = obj[:required] ? params.require(id) : params[id]

        handle_param validation, obj, val
      end

      validation
    }
  end

  def handle_param(validation, obj, val)
    obj => {id:}

    case val
    in ActionController::Parameters
      handle_param validation, obj, val.permit(:file, :path, :destination).to_hash.symbolize_keys
    in {file:, **rest}
      validation.objs.create! _id: id, file: file, **rest.slice(:destination)
    in {path: relative_path, **rest}
      template = Rails.application.config_for(:app).mass_dir_path_template!
      mass_dir = Pathname.new(template.gsub('{user}', current_user.uid))
      path     = mass_dir.join(relative_path)

      raise UnprocessableContent, "path must be in #{mass_dir}" unless mass_dir.contain?(path)

      destination = rest[:destination]

      if obj[:multiple] && path.directory?
        path.glob('**/*').reject(&:directory?).each do |fpath|
          destination = [
            destination,
            fpath.relative_path_from(path).dirname.to_s
          ].reject { _1.blank? || _1 == '.' }.join('/').presence

          create_object validation, id, fpath, destination
        end
      else
        create_object validation, id, path, destination
      end
    in Array if obj[:multiple]
      val.each do |v|
        handle_param validation, obj, v
      end
    in nil unless obj[:required]
      # do nothing
    in unknown
      raise UnprocessableContent, "unexpected parameter format in #{id}: #{unknown.inspect}"
    end
  end

  def create_object(validation, obj_id, path, destination)
    validation.objs.create!(
      _id: obj_id,

      file: {
        io:       path.open,
        filename: path.basename
      },

      destination:
    )
  rescue Errno::ENOENT
    raise UnprocessableContent, "path does not exist: #{path}"
  rescue Errno::EISDIR
    raise UnprocessableContent, "path is directory: #{path}"
  end
end
