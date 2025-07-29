class BioSample::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: {writing: :biosample, reading: :biosample}
end
