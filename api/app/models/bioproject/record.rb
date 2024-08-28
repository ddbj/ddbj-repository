class BioProject::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :bioproject, reading: :bioproject }
end
