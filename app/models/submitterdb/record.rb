class SubmitterDB::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: {writing: :submitterdb, reading: :submitterdb}
end
