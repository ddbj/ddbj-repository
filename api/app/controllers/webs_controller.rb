class WebsController < ActionController::Base
  def show
    render file: Rails.root.join('public/web/index.html')
  end
end
