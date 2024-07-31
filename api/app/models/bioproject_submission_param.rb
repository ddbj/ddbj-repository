class BioProjectSubmissionParam < ApplicationRecord
  has_one :submission, as: :param, touch: true

  def as_json
    {
      umbrella:
    }
  end
end
