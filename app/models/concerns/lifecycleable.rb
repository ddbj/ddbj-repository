module Lifecycleable
  extend ActiveSupport::Concern

  included do
    enum :status, {
      submission_accepted:    5100,
      curating:               5200,
      accession_issued:       5300,
      private:                5400,
      public:                 5500,
      withdrawn:              5600,
      canceled:               5700,
      permanently_suppressed: 5800,
      temporarily_suppressed: 5900
    }, prefix: :status, validate: true

    # DRAFT: Spike 0.8 (status 5900 / suppressed の可視性確定) 待ち。確定後はここを差し替える。
    scope :publicly_visible, -> { status_public }
    scope :curator_visible,  -> { where.not(status: %i[status_canceled status_withdrawn]) }
  end
end
