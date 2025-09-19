Rails.application.routes.draw do
  root to: redirect('/web/')

  get 'auth/:provider/callback', to: 'sessions#create'
  get 'auth/failure',            to: 'sessions#failure'

  scope :api, defaults: {format: :json} do
    resource :api_key, only: [] do
      post :regenerate
    end

    resource :me, only: %i[show]

    resources :validations, only: %i[index show destroy] do
      scope module: 'validations' do
        collection do
          resource :via_file,        only: %i[create]
          resource :via_ddbj_record, only: %i[create]
        end

        get 'files/*path' => 'files#show', format: false, as: 'file'
      end
    end

    resources :submissions, only: %i[index show create] do
      resources :accessions, only: %i[show update], param: :number, shallow: true do
        resources :accession_renewals, only: %i[show create], shallow: true
      end
    end
  end

  get 'web/*paths', to: 'webs#show'

  get 'up' => 'rails/health#show', as: :rails_health_check
end
