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

      # The attachment is named by the route, not carried as a signed
      # blob id — so one record's id cannot be presented with another
      # record's blob, and an attachment no route names has no way in.
      get 'files/:name',
          to:          'submission_request_files#show',
          as:          :file,
          constraints: {name: /ddbj_record/}

      resources :messages, only: %i[index create] do
        # Reading the thread does not discharge it; saying so does.
        post :read, on: :collection

        get 'files/:id', to: 'message_files#show', as: :file
      end
      resource :reviewer_access, only: %i[show create destroy]

      # A closure is a thing that exists or does not, so creating and
      # destroying one reads as closing and reopening.
      resource :closure, only: %i[create destroy]
    end

    # Unauthenticated reviewer view — the request is looked up by its
    # unguessable share token, never by the current user. Messages are
    # deliberately NOT reachable from here.
    get 'reviews/:token',            to: 'reviews#show',       as: :review
    get 'reviews/:token/accessions', to: 'reviews#accessions', as: :review_accessions

    # Files on the same token as the rest of the reviewer's view, so
    # revoking the share revokes them. The name is constrained here as
    # well as mapped in the controller: an unknown one never reaches
    # Ruby.
    get 'reviews/:token/files/:name',
        to:          'reviews#file',
        as:          :review_file,
        constraints: {name: /ddbj_record|submission_record|flatfile_na|flatfile_aa/}

    resources :submissions, only: %i[index show] do
      resources :accessions, only: %i[index]

      get 'files/:name',
          to:          'submission_files#show',
          as:          :file,
          constraints: {name: /ddbj_record|flatfile_na|flatfile_aa/}
    end

    # `index` here is the cross-submission one — the nested route above
    # answers for a single submission. Both reach the same controller,
    # because the only difference is which entries are in scope.
    resources :accessions, only: %i[index show], param: :number, constraints: {number: %r{[^/]+}}

    # A set is submissions that belong together, and the people they
    # belong to — two lists that meet only here. See SubmissionSet for
    # why the permission story has no third place to live.
    resources :sets, only: %i[index show create update destroy] do
      resources :members, only: %i[create destroy], controller: 'set_members' do
        # Sending the invitation again mints a new token, so the link that
        # did not get used stops working. Creating a reminder, not
        # updating the member: what happens is that a mail goes out.
        resource :reminder, only: %i[create], controller: 'set_member_reminders'
      end

      # Keyed by the submission's own id rather than by the join row's:
      # from the client's side the thing being taken out of the set is
      # the submission, and the row that records it has no other use.
      resources :submissions,
                only:       %i[create destroy],
                controller: 'set_submissions',
                param:      :submission_request_id
    end

    # Where an invitation link lands. `show` is unauthenticated — the
    # person holding it may not have an account yet, and the page has to
    # be able to say what they are being invited to before it asks them
    # to make one.
    resources :invitations, only: %i[show], param: :token do
      resource :acceptance, only: %i[create], controller: 'invitation_acceptances'
    end

    # Direct upload, redrawn here rather than at Active Storage's own
    # path — and authenticated, which it never was. It mints a signed
    # blob id and a presigned PUT to anybody who asks.
    resource :direct_uploads, only: %i[create], controller: 'direct_uploads'

    resources :stats, only: %i[index]
  end

  namespace :admin do
    # The landing screen is the work queue, not a directory of features —
    # everything else in the nav is reachable from here.
    root to: 'my_queue#show'

    resource :my_queue, only: %i[show], controller: 'my_queue'

    resource :session, only: %i[new destroy]

    # A name for a set of ledger filters. There is no `show`: the chip
    # links straight at the ledger with the stored params, so a saved
    # view lands on an ordinary, shareable URL rather than on a page
    # only its owner can reach.
    resources :saved_views, only: %i[create update destroy]

    # The request detail is a four-tab workbench: one screen answers one
    # question (state / bulk edits / conversation / provenance) instead of
    # stacking every block on `show`.
    resources :submission_requests, only: %i[index show] do
      resources :messages, only: %i[create] do
        # Opening the thread does not discharge it; saying so does.
        post :read, on: :collection
      end

      # Following is per curator, so it is a singular resource under the
      # request rather than something with an id of its own.
      resource :subscription, only: %i[create destroy]

      # Claiming hangs off the request, not the submission: a request that
      # has not been applied yet has no submission to address, and those
      # are exactly the ones nobody has claimed.
      resource :assignment, only: %i[create]

      member do
        # One tab, two kinds of row: a BioSample submission's samples, an
        # ST.26 submission's entries. Separate paths because the URL
        # should say which one you are looking at.
        get :samples
        get :entries
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

        # The same, for an ST.26 submission's entries. Retracting one —
        # canceled or withdrawn — is what keeps it out of the flatfile.
        post :bulk_update_entries
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

    # The tool screen, plus the two GETs that answer "what would this
    # press cover?" — one for the live summary, one for the confirmation.
    resource :regenerate_flatfiles, only: %i[show create] do
      # POST for a read: the form carries the accession list, which is a
      # bulk paste that does not fit in a query string.
      post :preview

      get :confirm
    end

    resources :regenerate_flatfiles_runs, only: %i[show] do
      member do
        get :failures
      end
    end

    # One screen with three tabs (?tab=due|sent|template), so "was this
    # sent?" and "what does it say?" are not separate destinations. The
    # template still has its own endpoint because it is a different
    # resource being written — it just renders inside the same screen.
    resources :distribution_notices, only: %i[index new create]

    resource :distribution_notice_template, only: %i[update], path: 'distribution_notices/template'

    resources :migration_runs, only: %i[index show new create] do
      member do
        patch :abandon
        get   :failures
      end
    end

    resources :accession_issuance_runs, only: %i[show] do
      member do
        patch :dismiss
      end
    end

    # Downloads for curators. A session cookie rather than a token, which
    # is the whole reason the two logins are independent.
    get 'submission_requests/:submission_request_id/files/:name',
        to:          'files#submission_request',
        as:          :submission_request_file,
        constraints: {name: /ddbj_record/}

    get 'submissions/:submission_id/files/:name',
        to:          'files#submission',
        as:          :submission_file,
        constraints: {name: /ddbj_record|flatfile_na|flatfile_aa/}

    get 'messages/:message_id/files/:id', to: 'files#message', as: :message_file

    # Same story as the API's: authenticated, because redrawing Active
    # Storage's public one is not the same as leaving it where Rails put
    # it.
    resource :direct_uploads, only: %i[create], controller: 'direct_uploads'

    mount MissionControl::Jobs::Engine, at: '/jobs'
  end

  # The SPA is mounted at /web/ (Ember rootURL). Its shell is served by
  # WebsController (not statically) so the runtime config can be injected on boot;
  # see the Dockerfile. Both /web and /web/ serve the shell, matching the previous
  # behaviour where the static server answered index.html for either.
  get 'web(/*paths)', to: 'webs#show', constraints: ->(req) {
    !req.xhr? && req.format.html?
  }

  # The Disk service's own endpoints, redrawn because
  # `active_storage.draw_routes` took them with the blob routes — and
  # `blob.url` resolves through them wherever the service is Disk rather
  # than S3, which is the test environment. Their tokens are Active
  # Storage's own, minted per request and short-lived; there is nothing
  # here to authenticate against and nothing durable to hold.
  scope :rails do
    get 'active_storage/disk/:encoded_key/*filename' => 'active_storage/disk#show', as: :rails_disk_service
    put 'active_storage/disk/:encoded_token'         => 'active_storage/disk#update', as: :update_rails_disk_service
  end

  get 'up' => 'rails/health#show', as: :rails_health_check
end
