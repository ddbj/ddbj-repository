class Validations::FilesController < ApplicationController
  class NotFound < StandardError; end

  include ActiveStorage::SetCurrent if Rails.env.test?

  def show
    validation = current_user.validations.find(params[:validation_id])

    redirect_to find_file(validation.objs).url, allow_other_host: true
  end

  private

  def find_file(objs)
    raise NotFound unless obj = objs.find { _1.path == params[:path] }

    obj.file
  end
end
