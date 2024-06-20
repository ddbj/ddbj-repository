class DRMDB::ExtEntity < DRMDB::Record
  self.table_name = "ext_entity"

  belongs_to :ext_relation, optional: true, class_name: "DRMDB::ExtRelation", foreign_key: "ext_id"

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
