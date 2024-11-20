class DRMDB::AccessionEntity < DRMDB::Record
  self.table_name = "accession_entity"

  belongs_to :accession_relation, optional: true, class_name: "DRMDB::AccessionRelation", foreign_key: "acc_id", primary_key: "acc_id"

  enum :acc_type, {
    submission: "DRA",
    experiment: "DRX",
    run:        "DRR",
    analysis:   "DRZ"
  }
end
