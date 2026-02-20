using PathnameContain

class Validation < ApplicationRecord
  class UnprocessableContent < StandardError; end

  belongs_to :subject, polymorphic: true

  has_many :details, dependent: :destroy, class_name: 'ValidationDetail'

  validates :finished_at, presence: true, if: ->(validation) { validation.finished? || validation.canceled? }

  enum :progress, %w[running finished canceled].index_by(&:to_sym), validate: true

  scope :submitted, ->(submitted) {
    submitted ? where.associated(:submission) : where.missing(:submission)
  }

  scope :with_validity, -> {
    left_joins(:details).group(:id).select('validations.*', <<~SQL)
      CASE
        WHEN validations.progress != 'finished'                                    THEN NULL
        WHEN COUNT(CASE WHEN validation_details.severity = 'error' THEN 1 END) = 0 THEN 'valid'
        ELSE 'invalid'
      END AS validity
    SQL
  }
end
