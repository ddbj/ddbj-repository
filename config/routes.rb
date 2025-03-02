Rails.application.routes.draw do
  root to: redirect("/web/")

  resource :auth, only: %i[] do
    get :login
    get :callback
  end

  scope :api, defaults: { format: :json } do
    resource :api_key, only: %i[show] do
      post :regenerate
    end

    resource :me, only: %i[show]

    resources :validations, only: %i[index show destroy] do
      scope module: "validations" do
        collection do
          resource :via_file, only: %i[create]
        end

        get "files/*path" => "files#show", format: false, as: "file"
      end
    end

    resources :submissions, only: %i[index show create]
  end

  get "web/*paths", to: "webs#show"

  get "up" => "rails/health#show", as: :rails_health_check
end
