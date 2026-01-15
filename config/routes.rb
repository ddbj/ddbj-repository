Rails.application.routes.draw do
  root to: redirect('/web/')

  get 'auth/:provider/callback', to: 'sessions#create'
  get 'auth/failure',            to: 'sessions#failure'

  scope :api, defaults: {format: :json} do
    resource :api_key, only: [] do
      post :regenerate
    end

    resource :me, only: %i[show]

    resources :submission_requests, only: %i[index show create] do
      resource :submission, only: :create
    end

    resources :submission_updates, only: %i[show] do
      resource :submission, only: :update
    end

    resources :submissions, only: %i[index show] do
      resources :updates, only: %i[create], controller: 'submission_updates'
    end

    resources :stats, only: %i[index]
  end

  get 'web/*paths', to: 'webs#show'

  get 'up' => 'rails/health#show', as: :rails_health_check
end
