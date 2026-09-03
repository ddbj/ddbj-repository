using PathnameContain

class Validation < ApplicationRecord
  # Raised with a sentence for the submitter, so it is answered rather
  # than swallowed into a bare status.
  class UnprocessableContent < StandardError
    include PublicError
  end

  belongs_to :subject, polymorphic: true

  has_many :details, dependent: :destroy, class_name: 'ValidationDetail'

  validates :finished_at, presence: true, if: ->(validation) { validation.finished? || validation.canceled? }

  enum :progress, %w[running finished canceled].index_by(&:to_sym), validate: true

  # How long a check stands for. A submission is sent on the strength of
  # one that was run against the reference data and the rules of the
  # moment, and both move — so beyond this the answer describes a state of
  # the world that has gone, and the file has to be checked again before
  # it is handed over.
  FRESH_FOR = 1.day

  # Here rather than on the subject: neither question is about the thing
  # being checked. `with_validity` answers the first in SQL for a list;
  # this is the same question of one record, for the screen and the write
  # that both have to agree about it.
  def passed? = finished? && !details.exists?(severity: :error)

  def fresh? = finished_at.present? && finished_at > FRESH_FOR.ago

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
