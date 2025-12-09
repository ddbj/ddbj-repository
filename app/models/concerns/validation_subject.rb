module ValidationSubject
  extend ActiveSupport::Concern

  included do
    has_one :validation, dependent: :destroy, as: :subject
    has_one :validation_with_validity, -> { with_validity }, class_name: 'Validation', as: :subject

    enum :status, {
      waiting:            0,
      validating:         1,
      validation_failed:  2,
      ready_to_apply:     3,
      applying:           4,
      applied:            5,
      application_failed: 6,
      no_change:          7
    }

    scope :with_validity, -> {
      left_joins(
        validation: :details
      ).group(
        "#{quoted_table_name}.id"
      ).select("#{quoted_table_name}.*", <<~SQL)
        CASE
          WHEN validations.progress != 'finished'                                    THEN NULL
          WHEN COUNT(CASE WHEN validation_details.severity = 'error' THEN 1 END) = 0 THEN 'valid'
          ELSE 'invalid'
        END AS validity
      SQL
    }

    scope :valid_only, -> {
      with_validity.having("validity = 'valid'")
    }
  end
end
