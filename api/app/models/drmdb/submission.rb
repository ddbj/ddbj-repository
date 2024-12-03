class DRMDB::Submission < DRMDB::Record
  self.table_name = "submission"

  has_one  :submission_group, class_name: "DRMDB::SubmissionGroup", foreign_key: "sub_id"
  has_many :status_histories, class_name: "DRMDB::StatusHistory",   foreign_key: "sub_id"
end
