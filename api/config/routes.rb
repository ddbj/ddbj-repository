dbs = DB.map { _1[:id].downcase }

Rails.application.routes.draw do
  concern :via_file do
    collection do
      scope ':db', db: Regexp.union(*dbs) do
        resource :via_file, only: %i(create), path: 'via-file'
      end
    end
  end

  concern :get_file do
    get 'files/*path' => 'files#show', format: false, as: 'file'
  end

  resource :auth, only: %i() do
    get :login
    get :callback
  end

  scope :api, defaults: {format: :json} do
    resource :api_key, path: 'api-key', only: %i(show) do
      post :regenerate
    end

    resource :auth, only: %i() do
      post :login_by_access_token
    end

    resource :me, only: %i(show)

    resources :validations, only: %i() do
      scope module: 'validations' do
        concerns :via_file
      end
    end

    resources :submissions, only: %i(index show) do
      scope module: 'submissions' do
        concerns :via_file
        concerns :get_file
      end
    end

    resources :requests, only: %i(index show destroy) do
      scope module: 'requests' do
        concerns :get_file
      end
    end
  end

  get 'up' => 'rails/health#show', as: :rails_health_check
end
