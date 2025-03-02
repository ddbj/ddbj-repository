class DRASearch::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :drasearch, reading: :drasearch }
end
