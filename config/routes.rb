Rails.application.routes.draw do
  root to: redirect('/web/')

  get 'auth/:provider/callback', to: 'sessions#create'
  get 'auth/failure',            to: 'sessions#failure'

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

      resources :submission_updates, only: %i[show] do
        resource :submission, only: :update
      end

      resources :submissions, only: %i[index show] do
        resources :accessions, only: %i[index]
        resources :updates,    only: %i[create], controller: 'submission_updates'
      end
    end

    resources :accessions, only: %i[show], param: :number, constraints: {number: %r{[^/]+}}

    resources :stats, only: %i[index]
  end

  namespace :admin do
    root to: 'dashboard#show'

    resource :session, only: %i[new destroy]

    resources :submission_requests, only: %i[index]
    resources :submissions,         only: %i[index]
    resources :users,               only: %i[index show update], param: :uid do
      resource :proxy_login, only: %i[create]
    end

    resource :regenerate_flatfiles, only: %i[show create]

    mount MissionControl::Jobs::Engine, at: '/jobs'
  end

  # The SPA is mounted at /web/ (Ember rootURL). Its shell is served by
  # WebsController (not statically) so the runtime config can be injected on boot;
  # see the Dockerfile. Both /web and /web/ serve the shell, matching the previous
  # behaviour where the static server answered index.html for either.
  get 'web(/*paths)', to: 'webs#show', constraints: ->(req) {
    !req.xhr? && req.format.html?
  }

  get 'up' => 'rails/health#show', as: :rails_health_check
end
