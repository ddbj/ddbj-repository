module FileDownload
  class NotFound < StandardError; end

  extend ActiveSupport::Concern

  included do
    include ActiveStorage::SetCurrent if Rails.env.test?
  end

  def find_file(objs)
    raise NotFound unless obj = objs.find { _1.path == params[:path] }

    obj.file
  end
end
