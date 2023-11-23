using PathnameContain

module ViaFile
  extend ActiveSupport::Concern

  class Error < StandardError; end

  included do
    rescue_from Error do |e|
      render json: {
        error: e.message
      }, status: :bad_request
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render json: {
        error: e.message
      }, status: :unprocessable_entity
    end
  end

  def create_request_from_params
    ActiveRecord::Base.transaction {
      db      = DB.find { _1[:id].downcase == params.require(:db) }
      request = dway_user.requests.create!(db: db[:id], status: 'waiting')

      request.objs.create! _id: '_base'

      db[:objects].each do |obj|
        obj => {id:}
        val = obj[:optional] ? params[id] : params.require(id)

        handle_param request, obj, val
      end

      request
    }
  end

  private

  def handle_param(request, obj, val)
    obj => {id:}

    case val
    in {file:, **rest}
      request.objs.create! _id: id, file: file, **rest.slice(:destination)
    in {path: relative_path, **rest}
      user_home = Pathname.new(ENV.fetch('USER_HOME_DIR')).join(dway_user.uid)
      path      = user_home.join(relative_path)

      raise Error, "path must be in #{user_home}" unless user_home.contain?(path)

      request.objs.create! _id: id, file: {
        io:       path.open,
        filename: path.basename,
        **rest.slice(:destination)
      }
    in ActionController::Parameters
      handle_param request, obj, val.permit(:file, :path, :destination).to_hash.symbolize_keys
    in Array if obj[:multiple]
      val.each do |v|
        handle_param request, obj, v
      end
    in nil if obj[:optional]
      # do nothing
    in unknown
      raise Error, "unexpected parameter format in #{id}: #{unknown.inspect}"
    end
  end
end
