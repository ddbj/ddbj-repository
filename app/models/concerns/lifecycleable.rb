module Lifecycleable
  extend ActiveSupport::Concern

  # Canonical name → integer mapping. Lifted to a module constant so
  # callers that work generically across Project + Sample (e.g. the
  # admin index's cross-submission bulk action) don't have to pick
  # one model's `.statuses` arbitrarily.
  STATUSES = {
    'submission_accepted'    => 5100,
    'curating'               => 5200,
    'accession_issued'       => 5300,
    'private'                => 5400,
    'public'                 => 5500,
    'withdrawn'              => 5600,
    'canceled'               => 5700,
    'permanently_suppressed' => 5800,
    'temporarily_suppressed' => 5900
  }.freeze

  included do
    enum :status, STATUSES, prefix: :status, validate: true

    # TODO(spike-0.8): DRAFT scopes — visibility for Temporarily / Permanently
    # Suppressed records is unresolved (waiting on curator + Confluence 1899364353).
    # Pin current behavior via test/models/concerns/lifecycleable_test.rb so the
    # final answer surfaces as a visible diff. Do NOT wire into external-facing
    # endpoints until 0.8 resolves.
    scope :publicly_visible, -> { status_public }
    scope :curator_visible,  -> { where.not(status: %i[canceled withdrawn]) }
  end
end
