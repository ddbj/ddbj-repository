class DRMDB::Submission < DRMDB::Record
  self.table_name = "submission"

  has_many :status_histories, class_name: "DRMDB::StatusHistory", foreign_key: "sub_id"
end
