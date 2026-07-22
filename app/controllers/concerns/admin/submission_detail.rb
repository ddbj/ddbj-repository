module Admin
  # Loads the ivars the submission-detail partial
  # (admin/submissions/_detail) renders. The detail now lives inside the
  # request-keyed show (admin/submission_requests/show) so the request is
  # the single unit; a submission without a materialised chain (a
  # pre-Apply request) simply has no detail to load.
  module SubmissionDetail
    extend ActiveSupport::Concern

    # Canonicalisation walks every subtree and produces canonical bytes +
    # SHA-256 for each, which costs ~20s on a 7 MB record (BS 20K-sample
    # scale, see SSUB004153). Skip both display rows above this size and
    # surface a banner instead — the curator can still pull the raw
    # materialised JSON via the dedicated `materialised` action.
    CANONICAL_DISPLAY_SIZE_LIMIT = 1.megabyte

    private

    def load_submission_detail(submission)
      @submission = submission
      @updates    = submission.updates.order(:id).to_a

      # Samples list is paginated inside a turbo-frame so 20K-row BS
      # records don't blow up the page. `page_key: 'samples_page'`
      # namespaces the URL param. (pagy v43: option name is `page_key`
      # not `page_param`, and the value must be a String not a Symbol;
      # the wrong shape is silently ignored.)
      if submission.biosample_db?
        @samples_pagy, @samples = pagy(submission.samples.includes(:assignee).order(:id),
                                       page_key: 'samples_page', limit: 20)

        @accessioned_sample_count = submission.samples.where.not(accession: nil).count
      end

      begin
        @materialised = submission.materialised_record

        if @materialised
          # `@materialised_size` is the Oj :strict serialised byte length,
          # cached in an ivar so the view's size badge does not re-encode.
          @materialised_size = Oj.dump(@materialised, mode: :strict).bytesize

          if @materialised_size <= CANONICAL_DISPLAY_SIZE_LIMIT
            @canonical_bytes = DDBJRecord::Canonicalizer.canonicalize(@materialised)
            # Hash the already-computed canonical bytes instead of calling
            # Canonicalizer.sha256, which re-canonicalises from scratch.
            @sha256 = Digest::SHA256.hexdigest(@canonical_bytes)
          end
        end
      rescue Submission::MaterialisationFailed, DDBJRecord::Canonicalizer::Error => e
        @materialisation_error = e
      end
    end
  end
end
