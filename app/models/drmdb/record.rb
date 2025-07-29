class DRMDB::Record < ApplicationRecord
  self.abstract_class = true

  connects_to database: {writing: :drmdb, reading: :drmdb}
end
