module Admin
  # Shared plumbing for every screen that renders the request table —
  # "All requests", "My queue" and each "Needs action" bucket. They differ
  # only in the scope they start from, so pagination, eager loading and
  # the per-BS-submission sample aggregate live here once.
  module RequestListing
    extend ActiveSupport::Concern

    # Per-BS-submission aggregate of (status, assignee) across samples, so
    # a list can show "Uniform: public / kodama" vs "Mixed (3)" without
    # hauling every Sample row over the wire. One SQL for the whole page —
    # no N+1, no per-row distinct() calls.
    SampleAggregate = Data.define(:statuses, :assignee_ids, :first_accession, :accession_count)

    private

    def load_requests(scope)
      @pagy, @requests   = pagy(scope.includes(:user, submission: [{project: :assignee}, :accessions]))
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
               Arel.sql('ARRAY_AGG(DISTINCT assignee_id) AS assignee_ids'),
               Arel.sql('MIN(accession) AS first_accession'),
               Arel.sql('COUNT(accession) AS accession_count'))

      rows.to_h {|sid, statuses, assignees, first_accession, accession_count|
        [sid, SampleAggregate.new(statuses:, assignee_ids: assignees, first_accession:, accession_count:)]
      }
    end
  end
end
