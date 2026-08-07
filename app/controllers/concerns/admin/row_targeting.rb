module Admin
  # Resolves what "the chosen rows" means when a submission's rows screen
  # posts a bulk action — the Samples tab for BioSample, the Entries tab
  # for ST.26. The two screens differ in what a row is called and not at
  # all in what selecting one means.
  #
  # The screen offers two scopes and they are not interchangeable:
  # `selected` is the checkboxes on the current page, `filtered` is every
  # row matching the current filter — which can be 100K rows the browser
  # never saw. The filtered set is therefore re-derived here from the
  # filter params riding in the action URL, never from a posted id list,
  # so the button means what its label says.
  module RowTargeting
    extend ActiveSupport::Concern

    private

    SCOPES = %w[selected filtered].freeze

    class UnknownScope < StandardError; end

    # The submission's curation rows and the search that narrows them, or
    # nil for a database that has neither — a BioProject has one Project,
    # not a bag of anything.
    def submission_rows(submission)
      case submission.db
      when 'biosample' then [submission.samples, SampleSearch]
      when 'st26'      then [submission.entries, EntrySearch]
      end
    end

    def rows_screen_path(submission, params = {})
      case submission.db
      when 'biosample' then samples_admin_submission_request_path(submission.request, params)
      when 'st26'      then entries_admin_submission_request_path(submission.request, params)
      end
    end

    # nil = "the whole submission", which is what callers outside the rows
    # screen want — the workbench's own Issue button posts no `bulk_row`
    # at all.
    #
    # A scope that is present but unrecognised is NOT that: a stale
    # bookmarked form or a garbled POST would otherwise widen a handful of
    # checked rows into all 100K, and an accession issuance cannot be taken
    # back once the Sequence has moved.
    def target_rows(submission)
      rows, search = submission_rows(submission)
      return nil unless rows

      case scope = params.dig(:bulk_row, :scope).presence
      when nil        then nil
      when 'selected' then rows.where(id: selected_row_ids)
      when 'filtered' then search.new(rows, params).scope
      else                 raise UnknownScope, "Unknown target: #{scope.inspect}."
      end
    end

    def selected_row_ids
      Array(params.dig(:bulk_row, :ids)).map(&:to_i).reject(&:zero?)
    end

    # "Apply to 0 selected rows" is a mis-click, not an instruction — an
    # update_all that touches nothing would report success and leave the
    # curator wondering which of the two scopes they were on.
    def empty_selection?
      params.dig(:bulk_row, :scope) == 'selected' && selected_row_ids.empty?
    end

    def from_rows_screen? = params[:bulk_row].present?

    # Bulk actions started on a rows tab land back on it, filter intact;
    # everything else goes to the request's Overview.
    def submission_return_path(submission)
      rows, search = submission_rows(submission)

      return admin_submission_request_path(submission.request) unless from_rows_screen? && rows

      rows_screen_path(submission, search.new(rows, params).to_params)
    end
  end
end
