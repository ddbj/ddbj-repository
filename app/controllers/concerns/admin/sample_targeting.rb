module Admin
  # Resolves what "the chosen samples" means when the Samples screen posts
  # a bulk action.
  #
  # The screen offers two scopes and they are not interchangeable:
  # `selected` is the checkboxes on the current page, `filtered` is every
  # row matching the current filter — which can be 100K rows the browser
  # never saw. The filtered set is therefore re-derived here from the
  # filter params riding in the action URL, never from a posted id list,
  # so the button means what its label says.
  module SampleTargeting
    extend ActiveSupport::Concern

    private

    SCOPES = %w[selected filtered].freeze

    class UnknownScope < StandardError; end

    # nil = "the whole submission", which is what callers outside the
    # Samples screen want — the workbench's own Issue button posts no
    # `bulk_sample` at all.
    #
    # A scope that is present but unrecognised is NOT that: a stale
    # bookmarked form or a garbled POST would otherwise widen a handful of
    # checked rows into all 100K, and an accession issuance cannot be taken
    # back once the Sequence has moved.
    def target_samples(submission)
      return nil unless submission.biosample_db?

      case scope = params.dig(:bulk_sample, :scope).presence
      when nil        then nil
      when 'selected' then submission.samples.where(id: selected_sample_ids)
      when 'filtered' then SampleSearch.new(submission.samples, params).scope
      else                 raise UnknownScope, "Unknown target: #{scope.inspect}."
      end
    end

    def selected_sample_ids
      Array(params.dig(:bulk_sample, :sample_ids)).map(&:to_i).reject(&:zero?)
    end

    # "Apply to 0 selected rows" is a mis-click, not an instruction — an
    # update_all that touches nothing would report success and leave the
    # curator wondering which of the two scopes they were on.
    def empty_selection?
      params.dig(:bulk_sample, :scope) == 'selected' && selected_sample_ids.empty?
    end

    def from_samples_screen? = params[:bulk_sample].present?

    # Bulk actions started on the Samples tab land back on it, filter
    # intact; everything else goes to the request's Overview.
    def submission_return_path(submission)
      return admin_submission_request_path(submission.request) unless from_samples_screen?

      samples_admin_submission_request_path(submission.request, SampleSearch.new(submission.samples, params).to_params)
    end
  end
end
