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
    alice = create(:user, uid: "alice")

    request.headers["Authorization"] = "Bearer #{alice.token}"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("alice")
  end

  example "admin can login as proxy" do
    alice = create(:user, uid: "alice", admin: true)

    create :user, uid: "bob"

    request.headers["Authorization"]  = "Bearer #{alice.token}"
    request.headers["X-Dway-User-Id"] = "bob"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("bob")
  end

  example "other user cannot login as proxy" do
    alice = create(:user, uid: "alice", admin: false)

    create :user, uid: "bob"

    request.headers["Authorization"]  = "Bearer #{alice.token}"
    request.headers["X-Dway-User-Id"] = "bob"

    get :index

    expect(response).to have_http_status(:ok)
    expect(controller.current_user.uid).to eq("alice")
  end
end
