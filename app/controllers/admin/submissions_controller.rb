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
  end
end
