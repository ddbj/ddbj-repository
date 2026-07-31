module Admin
  # Shared plumbing for every screen that renders the request table —
  # "All requests", "My queue" and each "Needs action" bucket. They differ
  # only in the scope they start from, so pagination, eager loading and
  # the per-BS-submission sample aggregate live here once.
  module RequestListing
    extend ActiveSupport::Concern

    # Per-BS-submission aggregate of status + accessions across samples, so
    # a list can show "Uniform: public" vs "Mixed (3)" without hauling
    # every Sample row over the wire. One SQL for the whole page — no N+1,
    # no per-row distinct() calls. (Assignee is not here: it is one column
    # on the request, so it needs no aggregate.)
    SampleAggregate = Data.define(:statuses, :first_accession, :accession_count)

    private

    def load_requests(scope)
      @pagy, @requests   = pagy(scope.includes(:user, :assignee, submission: %i[project accessions]))
      @sample_aggregates = sample_aggregates_for(@requests.filter_map(&:submission))
    end

    def sample_aggregates_for(submissions)
      bs_ids = submissions.select(&:biosample_db?).map(&:id)
      return {} if bs_ids.empty?

      rows = Sample
        .where(submission_id: bs_ids)
        .group(:submission_id)
        .pluck(:submission_id,
               Arel.sql('ARRAY_AGG(DISTINCT status) AS statuses'),
               Arel.sql('MIN(accession) AS first_accession'),
               Arel.sql('COUNT(accession) AS accession_count'))

      rows.to_h {|sid, statuses, first_accession, accession_count|
        [sid, SampleAggregate.new(statuses:, first_accession:, accession_count:)]
      }
    end
  end
end
