require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def index
      render plain: "hello"
    end
  end

  example "unauthorized" do
    get :index

    expect(response).to have_http_status(:unauthorized)
  end

  example "authorized" do
    create :user, uid: "alice", api_key: "API_KEY"

    request.headers["Authorization"] = "Bearer API_KEY"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("alice")
  end

  example "admin can login as proxy" do
    create :user, uid: "alice", api_key: "API_KEY", admin: true
    create :user, uid: "bob"

    request.headers["Authorization"]  = "Bearer API_KEY"
    request.headers["X-Dway-User-Id"] = "bob"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("bob")
  end

  example "other user cannot login as proxy" do
    create :user, uid: "alice", api_key: "API_KEY", admin: false
    create :user, uid: "bob"

    request.headers["Authorization"]  = "Bearer API_KEY"
    request.headers["X-Dway-User-Id"] = "bob"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("alice")
  end
end
