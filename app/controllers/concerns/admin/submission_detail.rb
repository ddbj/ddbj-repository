module Admin
  # Loads the pieces of a submission that the workbench tabs render.
  #
  # Split per tab on purpose: replaying the patch chain and canonicalising
  # it is the expensive part of this page, and only Overview (which shows
  # the hold date) and Record & history (which shows the digest) need it.
  # Samples and Messages skip it entirely.
  module SubmissionDetail
    extend ActiveSupport::Concern

    # Canonicalisation walks every subtree and produces canonical bytes +
    # SHA-256 for each, which costs ~20s on a 7 MB record (BS 20K-sample
    # scale, see SSUB004153). Skip both display rows above this size and
    # surface a banner instead — the curator can still pull the raw
    # materialised JSON via the dedicated `materialised` action.
    CANONICAL_DISPLAY_SIZE_LIMIT = 1.megabyte

    private

    # The materialised v3 record plus its serialised size. Sets
    # `@materialisation_error` instead of raising so a poisoned chain
    # still renders a page the curator can diagnose from.
    def load_materialised(submission)
      @materialised = submission.materialised_record

      # `@materialised_size` is the Oj :strict serialised byte length,
      # cached in an ivar so the view's size badge does not re-encode.
      @materialised_size = Oj.dump(@materialised, mode: :strict).bytesize if @materialised
    rescue Submission::MaterialisationFailed, DDBJRecord::Canonicalizer::Error => e
      @materialisation_error = e
    end

    def load_record_detail(submission)
      @updates = submission.updates.order(:id).to_a

      load_materialised(submission)
      return unless @materialised && @materialised_size <= CANONICAL_DISPLAY_SIZE_LIMIT

      begin
        @canonical_bytes = DDBJRecord::Canonicalizer.canonicalize(@materialised)
        # Hash the already-computed canonical bytes instead of calling
        # Canonicalizer.sha256, which re-canonicalises from scratch.
        @sha256 = Digest::SHA256.hexdigest(@canonical_bytes)
      rescue DDBJRecord::Canonicalizer::Error => e
        @materialisation_error = e
      end
    end
  end
end
