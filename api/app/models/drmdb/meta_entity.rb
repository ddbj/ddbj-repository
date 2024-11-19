class DRMDB::MetaEntity < DRMDB::Record
  self.table_name         = "meta_entity"
  self.inheritance_column = nil

  belongs_to :accession_relation, class_name: "DRMDB::AccessionRelation", foreign_key: "acc_id", primary_key: "acc_id"
end
