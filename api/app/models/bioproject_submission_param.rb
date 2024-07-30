class BioProjectSubmissionParam < ApplicationRecord
  has_one :submission, as: :database, touch: true
end
