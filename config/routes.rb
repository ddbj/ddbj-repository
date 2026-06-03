Rails.application.routes.draw do
  root to: redirect('/web/')

  get 'auth/:provider/callback', to: 'sessions#create'
  get 'auth/failure',            to: 'sessions#failure'

  resource :session, only: %i[destroy]

  scope :api, defaults: {format: :json} do
    resource :api_key, only: [] do
      post :regenerate
    end

    resource :me, only: %i[show]

    scope ':db', constraints: {db: Regexp.union(Submission.dbs.keys)} do
      resources :submission_requests, only: %i[index show create] do
        resource :status,     only: :show
        resource :submission, only: :create
      end

      resources :submissions, only: %i[index show] do
        resources :accessions, only: %i[index]
      end
    end

    resources :accessions, only: %i[show], param: :number, constraints: {number: %r{[^/]+}}

    resources :stats, only: %i[index]
  end

  namespace :admin do
    root to: 'dashboard#show'

    resource :session, only: %i[new]

    resources :submission_requests, only: %i[index]
    resources :submissions, only: %i[index show] do
      member do
        get :materialised
      end
    end
    resources :users,               only: %i[index show update], param: :uid do
      resource :proxy_login, only: %i[create]
    end

    resource :regenerate_flatfiles, only: %i[show create]

    mount MissionControl::Jobs::Engine, at: '/jobs'
  end

  get 'web/*paths', to: 'webs#show'

  get 'up' => 'rails/health#show', as: :rails_health_check
end
