class MesController < ApplicationController
  def show
    render json: {
      uid: current_user.uid
    }
  end
end
