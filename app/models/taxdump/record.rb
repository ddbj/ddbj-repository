class Taxdump::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: {writing: :taxdump, reading: :taxdump}
end
