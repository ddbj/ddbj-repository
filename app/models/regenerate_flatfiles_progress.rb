class RegenerateFlatfilesProgress < ApplicationRecord
  def loading?
    processed + failed < total
  end

  def completed?
    total.positive? && processed + failed >= total
  end
end
