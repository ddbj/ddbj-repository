class DRMDB::AccessionEntity < DRMDB::Record
  self.table_name         = "accession_entity"
  self.inheritance_column = nil

  belongs_to :accession_relation, optional: true, class_name: "DRMDB::AccessionRelation", foreign_key: "acc_id", primary_key: "acc_id"
end
