class DRMDB::StatusHistory < DRMDB::Record
  self.table_name = "status_history"

  belongs_to :submission, class_name: "DRMDB::Submission", foreign_key: "sub_id"

  enum :status, {
    new:              100,
    meta_validated:   300,
    data_validating:  380,
    data_error:       390,
    data_validated:   400,
    acc_issued:       500,
    private_complete: 700,
    release_notifed:  750,
    public_complete:  800,
    cancel:           1000,
    suppress:         1100,
    killed:           1200
  }, prefix: true
end
