class DRMDB::AccessionRelation < DRMDB::Record
  self.table_name = "accession_relation"

  belongs_to :submission_group, class_name: "DRMDB::SubmissionGroup", foreign_key: "grp_id", primary_key: "grp_id"

  has_many :accession_entities, class_name: "DRMDB::AccessionEntity", foreign_key: "acc_id", primary_key: "acc_id"
  has_one  :meta_entity,        class_name: "DRMDB::MetaEntity",      foreign_key: "acc_id", primary_key: "acc_id"
end
