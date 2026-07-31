Rails.application.routes.draw do
  root to: redirect('/web/')

  get 'auth/:provider/callback', to: 'sessions#create'

  # HTML, and outside SessionsController: a failed login has no session to
  # authenticate against, and the person reading it may be a submitter.
  get 'auth/failure', to: 'auth_failures#show'

  scope :api, defaults: {format: :json} do
    resource :api_key, only: [] do
      post :regenerate
    end

    resource :me, only: %i[show]

    # Cross-request "you need to do something" summary, so the web client
    # can show it on every screen rather than only where the row happens
    # to be listed.
    resource :attention, only: %i[show]

    # Submission identifiers are globally unique, so the routes are flat
    # — no /:db scope. `index` accepts an optional `?db=xxx` query to
    # filter; `create` reads the target database from the request body.
    resources :submission_requests, only: %i[index show create] do
      resource  :status,          only: :show
      resource  :submission,      only: :create
      resources :messages,        only: %i[index create]
      resource  :reviewer_access, only: %i[show create destroy]

      # A closure is a thing that exists or does not, so creating and
      # destroying one reads as closing and reopening.
      resource :closure, only: %i[create destroy]
    end

    # Unauthenticated reviewer view — the request is looked up by its
    # unguessable share token, never by the current user. Messages are
    # deliberately NOT reachable from here.
    get 'reviews/:token',            to: 'reviews#show',       as: :review
    get 'reviews/:token/accessions', to: 'reviews#accessions', as: :review_accessions

    resources :submissions, only: %i[index show] do
      resources :accessions, only: %i[index]
    end

    resources :accessions, only: %i[show], param: :number, constraints: {number: %r{[^/]+}}

    resources :stats, only: %i[index]
  end

  namespace :admin do
    # The landing screen is the work queue, not a directory of features —
    # everything else in the nav is reachable from here.
    root to: 'my_queue#show'

    resource :my_queue, only: %i[show], controller: 'my_queue'

    resource :session, only: %i[new destroy]

    # The request detail is a four-tab workbench: one screen answers one
    # question (state / bulk edits / conversation / provenance) instead of
    # stacking every block on `show`.
    resources :submission_requests, only: %i[index show] do
      resources :messages, only: %i[create]

      # Claiming hangs off the request, not the submission: a request that
      # has not been applied yet has no submission to address, and those
      # are exactly the ones nobody has claimed.
      resource :assignment, only: %i[create]

      member do
        get :samples
        get :messages
        get :record
      end
    end

    resources :submissions, only: %i[show] do
      collection do
        # Cross-submission bulk: apply (status, assignee) to all
        # checkboxed rows on the request list. BP submissions update
        # their Project row; BS submissions update all their Samples.
        post :bulk_update

        # Cross-submission bulk accession issuance. Selected submissions
        # are walked through AccessionIssue (BP → 1 PRJDB; BS → all
        # un-accessioned samples get a SAMD).
        # Two steps: the confirmation names what would be allocated and
        # what would be skipped; only the second post starts the run.
        post :confirm_issue_accessions
        post :bulk_issue_accessions
      end

      member do
        get :materialised

        # Bulk-apply a (status, assignee) tuple to a BS submission's
        # samples. The target set is whatever the Samples screen has in
        # hand — the checkboxed rows, or every row matching the current
        # filter. Per-sample forms are still not offered: a submission can
        # carry 100K samples and content edits go through the TSV
        # round-trip.
        post :bulk_update_samples
      end

      # One curation state per submission — status, assignee, hold date and
      # the internal comment save together. They were four independent
      # forms with four save buttons; a curator changes them as one
      # decision, so they post as one.
      resource  :curation,           only: %i[update]
      resource  :submitters,         only: %i[update]
      resource  :project_record,     only: %i[update]
      # `confirm` is `new` reached by POST, because the Samples screen's
      # button rides inside a form whose checkbox selection has to come
      # with it.
      resources :accessions, only: %i[new show create], path: 'accession' do
        collection { post :confirm }
      end
      resource  :sample_tsv_export,  only: %i[show]

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

    # One screen with three tabs (?tab=due|sent|template), so "was this
    # sent?" and "what does it say?" are not separate destinations. The
    # template still has its own endpoint because it is a different
    # resource being written — it just renders inside the same screen.
    resources :distribution_notices, only: %i[index new create]

    resource :distribution_notice_template, only: %i[update], path: 'distribution_notices/template'

    resources :migration_runs, only: %i[index show new create] do
      member do
        patch :abandon
      end
    end

    resources :accession_issuance_runs, only: %i[show] do
      member do
        patch :dismiss
      end
    end

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
