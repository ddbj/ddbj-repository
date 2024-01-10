using PathnameContain

module ViaFile
  extend ActiveSupport::Concern

  class BadRequest < StandardError; end

  def create_request_from_params(user, params, purpose:)
    ActiveRecord::Base.transaction {
      unless db = DB.find { _1[:id] == params.require(:db) }
        raise BadRequest, "unknown db: #{params[:db]}"
      end

      request = user.requests.create!(db: db[:id], purpose:, status: 'waiting')

      request.objs.create! _id: '_base'

      db[:objects].each do |obj|
        obj => {id:}
        val = obj[:optional] ? params[id] : params.require(id)

        handle_param user, request, obj, val
      end

      request
    }
  end

  private

  def handle_param(user, request, obj, val)
    obj => {id:}

    case val
    in ActionController::Parameters
      handle_param user, request, obj, val.permit(:file, :path, :destination).to_hash.symbolize_keys
    in {file:, **rest}
      request.objs.create! _id: id, file: file, **rest.slice(:destination)
    in {path: relative_path, **rest}
      user_home = Pathname.new(ENV.fetch('USER_HOME_DIR')).join(user.uid)
      path      = user_home.join(relative_path)

      raise BadRequest, "path must be in #{user_home}" unless user_home.contain?(path)

      destination = rest[:destination]

      if obj[:multiple] && path.directory?
        path.glob('**/*').reject(&:directory?).each do |fpath|
          destination = [
            destination,
            fpath.relative_path_from(path).dirname.to_s
          ].reject { _1.blank? || _1 == '.' }.join('/').presence

          create_object request, id, fpath, destination
        end
      else
        create_object request, id, path, destination
      end
    in Array if obj[:multiple]
      val.each do |v|
        handle_param user, request, obj, v
      end
    in nil if obj[:optional]
      # do nothing
    in unknown
      raise BadRequest, "unexpected parameter format in #{id}: #{unknown.inspect}"
    end
  end

  def create_object(request, obj_id, path, destination)
    request.objs.create! **{
      _id: obj_id,

      file: {
        io:       path.open,
        filename: path.basename,
      },

      destination:
    }
  end
end
