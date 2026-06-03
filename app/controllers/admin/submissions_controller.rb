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
      effective_as_of  = @as_of_row&.id

      begin
        @materialised    = @submission.materialise_at(update_id: effective_as_of)
        @canonical_bytes = @materialised && DDBJRecord::Canonicalizer.canonicalize(@materialised)
        @sha256          = @materialised && DDBJRecord::Canonicalizer.sha256(@materialised)
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
