class DRMDB::StatusHistory < DRMDB::Record
  self.table_name = "status_history"

  belongs_to :submission, class_name: "DRMDB::Submission", foreign_key: "sub_id"

  enum :status, {
    new: 100
  }, prefix: true
end
