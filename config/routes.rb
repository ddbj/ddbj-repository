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

    # Submission identifiers are globally unique, so the routes are flat
    # — no /:db scope. `index` accepts an optional `?db=xxx` query to
    # filter; `create` reads the target database from the request body.
    resources :submission_requests, only: %i[index show create] do
      resource :status,     only: :show
      resource :submission, only: :create
    end

    resources :submissions, only: %i[index show] do
      resources :accessions, only: %i[index]
      resources :messages,   only: %i[index create]
    end

    resources :accessions, only: %i[show], param: :number, constraints: {number: %r{[^/]+}}

    resources :stats, only: %i[index]
  end

  namespace :admin do
    root to: 'dashboard#show'

    resource :session, only: %i[new]

    resources :submission_requests, only: %i[index]
    resources :submissions, only: %i[index show] do
      collection do
        # Cross-submission bulk: apply (status, assignee) to all
        # checkboxed rows on the index. BP submissions update their
        # Project row; BS submissions update all their Samples.
        patch :bulk_update

        # Cross-submission bulk accession issuance. Selected submissions
        # are walked through AccessionIssue (BP → 1 PRJDB; BS → all
        # un-accessioned samples get a SAMD).
        post :bulk_issue_accessions
      end

      member do
        get :materialised

        # Bulk-apply a (status, assignee) tuple to every Sample in a BS
        # submission. Per-sample editing is intentionally NOT exposed:
        # a submission can carry 20K samples and the typical curator
        # workflow advances them together (all curating → all
        # accession_issued → all public). Per-sample diversity is rare
        # enough to defer to a later UI.
        patch :bulk_update_samples
      end

      # Per-submission curator edits. BP submissions have one Project; the
      # singular nested resource is the natural URL for "edit THIS BP's
      # project metadata". BS / ST26 don't have a Project — the controller
      # 404s in those cases.
      resource  :project,            only: %i[update]
      resource  :curator_comment,    only: %i[update]
      resource  :submitters,         only: %i[update]
      resource  :hold_date,          only: %i[update]
      resource  :project_record,     only: %i[update]
      resource  :accession,          only: %i[create]
      resource  :sample_tsv_export,  only: %i[show]
      resources :messages,           only: %i[create]

      # Per-submission BS sample-bag editing via TSV round-trip. The
      # export endpoint above streams the current state; this endpoint
      # accepts the edited file and runs an async job.
      resources :sample_tsv_imports, only: %i[show create] do
        member do
          get :error_report
        end
      end
    end

    resources :users,               only: %i[index show update], param: :uid do
      resource :proxy_login, only: %i[create]
    end

    resource :regenerate_flatfiles, only: %i[show create]

    resources :migration_runs, only: %i[index show new create]

    mount MissionControl::Jobs::Engine, at: '/jobs'
  end

  get 'web/*paths', to: 'webs#show'

  get 'up' => 'rails/health#show', as: :rails_health_check
end
