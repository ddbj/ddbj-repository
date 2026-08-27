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
      @blocking  = RegenerateFlatfilesRun.without_numbers.in_flight.recent.first
      @run       = RegenerateFlatfilesRun.without_numbers.recent.first

      # The newest run is the panel, so it is not also a row: the panel
      # keeps itself up to date and the table does not, and the two
      # disagreeing about whether the run has finished is the sort of
      # thing that makes a screen not worth reading.
      @runs = RegenerateFlatfilesRun.without_numbers.recent.where.not(id: @run&.id).limit(10)
    end

    # The count, live, as the form is filled in. Its own endpoint rather
    # than a client-side guess: what "3 accession numbers" resolves to is
    # a question only the database can answer, and answering it wrongly
    # in the summary would be worse than not showing one.
    # POST for a read, because the thing being read is the accession
    # list: a bulk paste is thousands of numbers, and a query string that
    # long is refused by the proxy before it reaches here — which would
    # break the summary at exactly the scale it exists for.
    def preview
      render partial: 'summary', locals: {
        scope:    RegenerationScope.new(params),
        blocking: RegenerateFlatfilesRun.without_numbers.in_flight.recent.first
      }
    end

    def confirm
      @scope = RegenerationScope.new(params)
    end

    def create
      scope = build_scope

      # Two runs over one submission put two workers on the same record:
      # both rewrite the flatfile, both overwrite the LOCUS date, and
      # both write an accession history entry. The screen disables the
      # button while a run is going; this is the same rule for the press
      # that arrives anyway — a second tab, a back button, a double
      # submit of the confirmation.
      if (blocking = RegenerateFlatfilesRun.without_numbers.in_flight.recent.first)
        return redirect_to admin_regenerate_flatfiles_path,
                           alert: "A regeneration run started at #{helpers.format_datetime(blocking.started_at)} " \
                                  'is still going. Wait for it to finish.'
      end

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
      # The numbers are recorded for a retry to read back, so the rule
      # for which runs have any is the scope's — a list left in the box
      # under the every-submission option is a draft, and storing it
      # would have the retry date only those. Stored as the parsed list
      # rather than the paste, so the run and the form that made it count
      # the same numbers.
      #
      # `accession_count` comes off the list on save, through the same
      # parse a retry will run, so the two cannot drift apart.
      run = RegenerateFlatfilesRun.create!(
        actor:      current_actor,
        target:     scope.target,
        numbers:    (scope.numbers.join("\n") if scope.naming_accessions?),
        locus_date: scope.locus_date,
        total:      scope.total,
        started_at: Time.current,
        retry_of:   scope.retry_of
      )

      # In batches: the all-submissions scope is the whole table, and
      # materialising it to hand one array to perform_all_later is the
      # kind of allocation that only shows up on the day someone uses it.
      enqueued = 0

      # Only the id is ever read — the job carries a GlobalID — and the
      # every-submission scope is the whole table.
      scope.submissions.select(:id).find_in_batches(batch_size: 500) do |submissions|
        ActiveJob.perform_all_later submissions.map {|submission|
          RegenerateSubmissionFlatfilesJob.new(submission, current_user, run, scope.locus_date,
                                               accessions: scope.accessions_for(submission))
        }

        enqueued += submissions.size
      end

      # The total is what was enqueued, not what was counted a moment
      # earlier. A submission deleted in between would leave the run one
      # short of a total it can never reach, and the screen would report
      # "Regenerating…" for an hour before the stale bound noticed.
      run.update!(total: enqueued) unless enqueued == run.total
      run.finish_if_done!

      run
    end
  end
end
