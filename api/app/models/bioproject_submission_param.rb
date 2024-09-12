class BioProjectSubmissionParam < ApplicationRecord
  has_one :submission, as: :param, touch: true

  validates :umbrella, inclusion: { in: [ true, false ] }

  def as_json
    {
      umbrella:
    }
  end
end
