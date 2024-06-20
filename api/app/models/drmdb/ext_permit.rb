class DRMDB::ExtPermit < DRMDB::Record
  self.table_name = "ext_permit"

  belongs_to :ext_relation, optional: true, class_name: "DRMDB::ExtRelation", foreign_key: "ext_id"
end
