class DRMDB::ExtEntity < DRMDB::Record
  self.table_name = "ext_entity"

  has_many :ext_permits, class_name: "DRMDB::ExtPermit", foreign_key: "ext_id"

  enum :acc_type, {
    submission: "1",
    study:      "2",
    sample:     "3",
    experiment: "4",
    run:        "5",
    analysis:   "6"
  }, prefix: true

  enum :status, {
    valid: 100
  }, prefix: true
end
