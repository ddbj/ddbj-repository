class WebsController < ActionController::Base
  def show
    send_file Rails.root.join("public/web/index.html")
  end
end
