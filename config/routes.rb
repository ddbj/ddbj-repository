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
      collection do
        # Cross-submission bulk: apply (status, assignee) to all
        # checkboxed rows on the index. BP submissions update their
        # Project row; BS submissions update all their Samples.
        patch :bulk_update
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
      resource :project,  only: %i[update], controller: 'projects'

      # Curator edits to the record-level free-text comments (v3
      # `submission.comments: list[str]`). Goes through the patch chain
      # via Submission#append_update! — each save generates a new
      # SubmissionUpdate row instead of mutating the typed columns.
      resource :comments, only: %i[update], controller: 'comments'

      # Curator edits to v3 `submission.submitters: list[Person]`.
      # Same patch-chain semantics as comments — submitter form posts
      # a positional array; rebuild the submitters block and let
      # append_update! emit minimal RFC 6902 ops.
      resource :submitters, only: %i[update], controller: 'submitters'

      # Curator edit to v3 `submission.hold_date: str | None` (ISO
      # YYYY-MM-DD). Same patch-chain pattern as comments / submitters.
      resource :hold_date, only: %i[update], controller: 'hold_dates'
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
