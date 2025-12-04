class ValidationDetail < ApplicationRecord
  belongs_to :validation, inverse_of: :details

  enum :severity, %w[warning error].index_by(&:to_sym), validate: true
end
