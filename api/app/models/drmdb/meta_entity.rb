class DRMDB::MetaEntity < DRMDB::Record
  self.table_name = "meta_entity"

  belongs_to :accession_relation, class_name: "DRMDB::AccessionRelation", foreign_key: "acc_id"
end
