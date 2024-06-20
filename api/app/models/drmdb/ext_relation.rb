class DRMDB::ExtRelation < DRMDB::Record
  self.table_name = "ext_relation"

  belongs_to :submission_group, class_name: "DRMDB::SubmissionGroup", foreign_key: "grp_id"

  has_many :ext_entities, class_name: "DRMDB::ExtEntity", foreign_key: "ext_id"
  has_one  :ext_permit,   class_name: "DRMDB::ExtPermit", foreign_key: "ext_id"
end
