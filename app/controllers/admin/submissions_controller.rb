module Admin
  class SubmissionsController < ApplicationController
    def index
      # Project away `cached_materialised_record` (bytea, BS-scale ~7MB
      # per row) — the index view never reads it, and pagy(20) × 7MB =
      # 140MB transferred per page once caches are warmed.
      scope = Submission
        .select(Submission.column_names - %w[cached_materialised_record])
        .includes(:user)
        .order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?
      scope = filter_by_source_id(scope, params[:source_id]) if params[:source_id].present?
      scope = filter_by_accession(scope, params[:accession]) if params[:accession].present?

      @pagy, @submissions = pagy(scope)
    end

    # Canonicalisation walks every subtree and produces canonical bytes +
    # SHA-256 for each, which costs ~20s on a 7 MB record (BS 20K-sample
    # scale, see SSUB004153). Skip both display rows above this size and
    # surface a banner instead — the materialised record itself still
    # renders fine via plain JSON.pretty_generate.
    CANONICAL_DISPLAY_SIZE_LIMIT = 1.megabyte

    def show
      @submission = Submission.includes(:user).find(params[:id])
      @updates    = @submission.updates.order(:id).to_a
      latest_id   = @updates.last&.id

      # Treat ?as_of=<latest_id> as identical to no as_of at all — the
      # resulting snapshot IS the current state, so the "Viewing snapshot
      # at ..." banner would be misleading.
      requested        = parse_as_of(params[:as_of])
      @requested_as_of = requested unless requested == latest_id
      @as_of_row       = @requested_as_of && @updates.find {|u| u.id == @requested_as_of }

      # Samples list is paginated inside a turbo-frame so 20K-row BS
      # records don't blow up the page. `page_key: :samples_page`
      # namespaces the URL param so future paginators on the same page
      # (e.g. patch chain) won't collide. (pagy v43 renamed `page_param`
      # → `page_key`; the wrong name is silently ignored, see
      # Pagy::Request#page reading `@options[:page_key]`.)
      if @submission.biosample_db?
        @samples_pagy, @samples = pagy(@submission.samples.order(:id), page_key: 'samples_page', limit: 20)
      end

      begin
        # Cache-aware fast path on the latest snapshot; as_of snapshots
        # always replay because the cache stores only the latest.
        @materialised = @as_of_row ? @submission.materialise_at(update_id: @as_of_row.id) : @submission.materialised_record

        if @materialised
          dump_size = Oj.dump(@materialised, mode: :strict).bytesize

          if dump_size <= CANONICAL_DISPLAY_SIZE_LIMIT
            @canonical_bytes = DDBJRecord::Canonicalizer.canonicalize(@materialised)
            # Hash the already-computed canonical bytes instead of calling
            # Canonicalizer.sha256, which re-canonicalises from scratch.
            @sha256 = Digest::SHA256.hexdigest(@canonical_bytes)
          else
            @canonical_skipped_size = dump_size
          end
        end
      rescue Submission::MaterialisationFailed, DDBJRecord::Canonicalizer::Error => e
        @materialisation_error = e
      end
    end

    private

    # Strict positive-integer parser. Non-numeric or non-positive input is
    # discarded — the view treats `nil` as "no cutoff" and reports a banner
    # when the original `params[:as_of]` was provided but didn't resolve.
    def parse_as_of(raw)
      return nil if raw.blank?

      parsed = Integer(raw, 10, exception: false)
      parsed&.positive? ? parsed : nil
    end

    # Longer than any real PSUB/SSUB/PRJDB/SAMD/SAMN/etc. accession. Bounds
    # both the SQL ILIKE cost and the request-log payload for crafted/fuzzed
    # input.
    MAX_FILTER_LENGTH = 64

    # Coerce param input to a bounded, trimmed string. Non-String shapes
    # (Array, Hash, ActionController::Parameters) become '' so the calling
    # helpers no-op on them instead of raising NoMethodError on sanitize.
    def normalize_filter_value(raw)
      return '' unless raw.is_a?(String)

      raw.strip[0, MAX_FILTER_LENGTH] || ''
    end

    # Case-insensitive PREFIX match on submissions.source_id. Column name is
    # table-qualified so a future scope chain that joins a sibling table
    # with a same-named column does not trip Postgres ambiguous-column.
    def filter_by_source_id(scope, raw)
      value = normalize_filter_value(raw)
      return scope if value.empty?

      scope.where('submissions.source_id ILIKE ?', "#{sanitize_sql_like(value)}%")
    end

    # Case-insensitive PREFIX match OR-ed across the three accession-bearing
    # associations (projects for BP, samples for BS, accessions for ST26).
    # EXISTS subqueries avoid the row duplication a join would introduce
    # when a single submission has many matching samples / entries.
    def filter_by_accession(scope, raw)
      value = normalize_filter_value(raw)
      return scope if value.empty?

      pattern = "#{sanitize_sql_like(value)}%"
      scope.where(<<~SQL.squish, pattern:)
        EXISTS (SELECT 1 FROM projects   WHERE projects.submission_id   = submissions.id AND projects.accession   ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM samples    WHERE samples.submission_id    = submissions.id AND samples.accession    ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM accessions WHERE accessions.submission_id = submissions.id AND accessions.number    ILIKE :pattern)
      SQL
    end

    def sanitize_sql_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end
  end
end
