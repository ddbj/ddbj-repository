require "rails_helper"

RSpec.describe ValidationsController, type: :controller do
  def login(user)
    request.headers["Authorization"] = "Bearer #{user.token}"
  end

  describe "get :index" do
    describe "pagination" do
      let_it_be(:user) { create_default(:user) }

      before do
        login user
      end

      context "paginated" do
        before_all do
          create :validation, id: 100
          create :validation, id: 101
          create :validation, id: 102
          create :validation, id: 103
          create :validation, id: 104
        end

        before do
          stub_const "Pagy::DEFAULT", Pagy::DEFAULT.merge(limit: 2)
        end

        example "page=1" do
          get :index, as: :json

          expect(response).to have_http_status(:ok)
          expect(assigns(:validations).pluck(:id)).to eq([ 104, 103 ])

          expect(response.headers["Link"].split(/,\s*/)).to contain_exactly(
            '<http://test.host/api/validations?page=1>; rel="first"',
            '<http://test.host/api/validations?page=3>; rel="last"',
            '<http://test.host/api/validations?page=2>; rel="next"'
          )
        end

        example "page=2" do
          get :index, params: { page: 2 }, as: :json

          expect(response).to have_http_status(:ok)
          expect(assigns(:validations).pluck(:id)).to eq([ 102, 101 ])

          expect(response.headers["Link"].split(/,\s*/)).to contain_exactly(
            '<http://test.host/api/validations?page=1>; rel="first"',
            '<http://test.host/api/validations?page=3>; rel="last"',
            '<http://test.host/api/validations?page=1>; rel="prev"',
            '<http://test.host/api/validations?page=3>; rel="next"'
          )
        end

        example "page=3" do
          get :index, params: { page: 3 }, as: :json

          expect(response).to have_http_status(:ok)
          expect(assigns(:validations).pluck(:id)).to eq([ 100 ])

          expect(response.headers["Link"].split(/,\s*/)).to contain_exactly(
            '<http://test.host/api/validations?page=1>; rel="first"',
            '<http://test.host/api/validations?page=3>; rel="last"',
            '<http://test.host/api/validations?page=2>; rel="prev"'
          )
        end

        example "out of range" do
          get :index, params: { page: 4 }, as: :json

          expect(response).to have_http_status(:bad_request)

          expect(response.parsed_body.deep_symbolize_keys).to eq(
            error: "expected :page in 1..3; got 4"
          )
        end
      end

      context "single page" do
        before_all do
          create :validation, id: 100
        end

        example do
          get :index, as: :json

          expect(response).to have_http_status(:ok)

          expect(response.headers["Link"].split(/,\s*/)).to contain_exactly(
            '<http://test.host/api/validations?page=1>; rel="first"',
            '<http://test.host/api/validations?page=1>; rel="last"'
          )
        end
      end
    end

    describe "search" do
      context "by normal user" do
        let_it_be(:user) { create_default(:user, admin: false) }

        before do
          login user
        end

        example "everyone" do
          create :validation, id: 100
          create :validation, id: 101, user: create(:user)

          get :index, params: { everyone: true }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100)
        end

        example "uid" do
          create :validation, id: 100
          create :validation, id: 101, user: create(:user, uid: "bob")

          get :index, params: { everyone: true, uid: "bob" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100)
        end

        example "db" do
          create :validation, id: 100, db: "JVar"
          create :validation, id: 101, db: "MetaboBank"
          create :validation, id: 102, db: "Trad"

          get :index, params: { db: "JVar,MetaboBank" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100, 101)
        end

        example "created_at" do
          create :validation, id: 100, created_at: "2024-01-02 03:04:05"
          create :validation, id: 101, created_at: "2024-01-03 03:04:05"
          create :validation, id: 102, created_at: "2024-01-04 03:04:05"

          get :index, params: {
            created_at_after:  "2024-01-03 00:00:00"
          }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(101, 102)

          get :index, params: {
            created_at_before: "2024-01-03 23:59:59"
          }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100, 101)

          get :index, params: {
            created_at_after:  "2024-01-03 00:00:00",
            created_at_before: "2024-01-03 23:59:59"
          }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(101)
        end

        example "progress" do
          create :validation, id: 100, progress: "waiting"
          create :validation, id: 101, progress: "running"
          create :validation, id: 102, progress: "finished"

          get :index, params: { progress: "waiting" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100)

          get :index, params: { progress: "running,finished" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(101, 102)
        end

        example "validity" do
          create :validation, id: 100, validity: "valid"
          create :validation, id: 101, validity: nil

          get :index, params: { validity: "valid" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100)
        end

        example "submitted" do
          create :validation, :valid, id: 100 do |validation|
            create :submission, validation:
          end

          create :validation, id: 101

          get :index, params: { submitted: true }, as: :json

          expect(response).to have_http_status(:ok)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100)

          get :index, params: { submitted: false }, as: :json

          expect(response).to have_http_status(:ok)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(101)
        end
      end

      context "by admin" do
        let_it_be(:user) { create_default(:user, admin: true) }

        before do
          login user
        end

        before do
          create :validation, id: 100
          create :validation, id: 101, user: create(:user, uid: "bob")
          create :validation, id: 102, user: create(:user, uid: "carol")
        end

        example "everyone" do
          get :index, params: { everyone: true }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(100, 101, 102)
        end

        example "uid" do
          get :index, params: { everyone: true, uid: "bob,carol" }, as: :json

          expect(response).to have_http_status(200)
          expect(assigns(:validations).pluck(:id)).to contain_exactly(101, 102)
        end
      end
    end
  end
end
