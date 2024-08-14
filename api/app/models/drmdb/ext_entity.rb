class DRMDB::ExtEntity < DRMDB::Record
  self.table_name = "ext_entity"

  has_many :ext_permits, class_name: "DRMDB::ExtPermit", foreign_key: "ext_id"

  enum :acc_type, {
    study:      "PSUB",
    sample:     "SSUB",
    submission: "DRA"
  }, prefix: true

  enum :status, {
    inputting: 0,
    valid:     100
  }, prefix: true
end
