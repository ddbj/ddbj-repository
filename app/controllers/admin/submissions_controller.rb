module Admin
  class SubmissionsController < ApplicationController
    def index
      scope = Submission.includes(:user).order(id: :desc)
      scope = scope.where(db: params[:db]) if params[:db].present?
      scope = scope.where(user: User.where(uid: params[:user])) if params[:user].present?

      @pagy, @submissions = pagy(scope)
    end

    def show
      @submission      = Submission.includes(:user).find(params[:id])
      @updates         = @submission.updates.order(:id).to_a
      @requested_as_of = parse_as_of(params[:as_of])
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
