module Admin
  class RegenerateFlatfilesController < ApplicationController
    # Typed out in full for the one scope that cannot be taken back by
    # pressing it again. Three submissions is a click; every submission
    # in the database is a decision, and the difference should cost
    # something.
    CONFIRM_PHRASE = 'all'.freeze

    def show
      @scope     = RegenerationScope.new(params)
      @all_total = RegenerationScope.regeneratable.count
      @run       = RegenerateFlatfilesRun.recent.first

      # The newest run is the panel, so it is not also a row: the panel
      # keeps itself up to date and the table does not, and the two
      # disagreeing about whether the run has finished is the sort of
      # thing that makes a screen not worth reading.
      @runs = RegenerateFlatfilesRun.recent.where.not(id: @run&.id).limit(10)
    end

    # The count, live, as the form is filled in. Its own endpoint rather
    # than a client-side guess: what "3 accession numbers" resolves to is
    # a question only the database can answer, and answering it wrongly
    # in the summary would be worse than not showing one.
    def preview
      render partial: 'summary', locals: {scope: RegenerationScope.new(params)}
    end

    def confirm
      @scope = RegenerationScope.new(params)
    end

    def create
      scope = build_scope

      unless scope.ready?
        return redirect_to admin_regenerate_flatfiles_path,
                           alert: "Nothing to regenerate — #{scope.problems.first || 'the scope was empty'}"
      end

      # The phrase is checked here and not only in the dialog: the dialog
      # disables a button, and a disabled button is a courtesy rather
      # than a rule.
      if scope.all_target? && params[:confirm].to_s.strip.downcase != CONFIRM_PHRASE
        return redirect_to admin_regenerate_flatfiles_path,
                           alert: "Type #{CONFIRM_PHRASE} to confirm regenerating every flatfile."
      end

      run = start(scope)

      redirect_to admin_regenerate_flatfiles_path,
                  notice: "Regenerating #{helpers.pluralize(run.total, 'submission')}.",
                  status: :see_other
    end

    private

    def build_scope
      if (previous = params[:retry_of].presence)
        # A retry re-runs what failed with the options that produced the
        # failures, not with whatever the form happens to be showing —
        # otherwise "retry the 6 failed" would quietly become a different
        # run that happens to cover the same six.
        RegenerationScope.retrying(RegenerateFlatfilesRun.find(previous))
      else
        RegenerationScope.new(params)
      end
    end

    def start(scope)
      run = RegenerateFlatfilesRun.create!(
        actor:      current_actor,
        target:     scope.target,
        numbers:    (scope.numbers_text if scope.accessions_target?),
        locus_date: scope.locus_date,
        force:      scope.force,
        total:      scope.total,
        started_at: Time.current,
        retry_of:   scope.retry_of
      )

      # In batches: the all-submissions scope is the whole table, and
      # materialising it to hand one array to perform_all_later is the
      # kind of allocation that only shows up on the day someone uses it.
      scope.submissions.find_in_batches(batch_size: 500) do |submissions|
        ActiveJob.perform_all_later submissions.map {|submission|
          RegenerateSubmissionFlatfilesJob.new(submission, current_user, run, scope.locus_date, force: scope.force)
        }
      end

      run
    end
  end
end
