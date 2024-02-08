Rails.application.routes.draw do
  concern :via_file do
    collection do
      resource :via_file, only: %i(create), path: 'via-file'
    end
  end

  concern :get_file do
    get 'files/*path' => 'files#show', format: false, as: 'file'
  end

  root to: redirect('/web/')

  resource :auth, only: %i() do
    get :login
    get :callback
  end

  scope :api, defaults: {format: :json} do
    resource :api_key, path: 'api-key', only: %i(show) do
      post :regenerate
    end

    resource :me, only: %i(show)

    resources :validations, only: %i(index show destroy) do
      scope module: 'validations' do
        concerns :via_file
        concerns :get_file
      end
    end

    resources :submissions, only: %i(index show create)

    namespace :admin do
      resources :validations, only: %i(index)
    end
  end

  get 'web/*paths', to: 'webs#show'

  get 'up' => 'rails/health#show', as: :rails_health_check
end
