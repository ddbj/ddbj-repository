module ValidationSubject
  extend ActiveSupport::Concern

  included do
    has_one :validation, dependent: :destroy, as: :subject
    has_one :validation_with_validity, -> { with_validity }, class_name: 'Validation', as: :subject

    enum :status, {
      waiting_validation:  0,
      validating:          1,
      validation_failed:   2,
      ready_to_apply:      3,
      waiting_application: 4,
      applying:            5,
      applied:             6,
      application_failed:  7,
      no_change:           8
    }

    scope :with_validity, -> {
      left_joins(
        validation: :details
      ).group(
        "#{quoted_table_name}.id"
      ).select("#{quoted_table_name}.*", <<~SQL)
        CASE
          WHEN MAX(validations.progress) != 'finished'                               THEN NULL
          WHEN COUNT(CASE WHEN validation_details.severity = 'error' THEN 1 END) = 0 THEN 'valid'
          ELSE 'invalid'
        END AS validity
      SQL
    }

    scope :valid_only, -> {
      with_validity.having(<<~SQL)
        MAX(validations.progress) = 'finished' AND COUNT(
          CASE WHEN validation_details.severity = 'error' THEN 1 END
        ) = 0
      SQL
    }

    def processing?
      status.in?(%w[
        waiting_validation
        validating
        waiting_application
        applying
      ])
    end
  end
end
