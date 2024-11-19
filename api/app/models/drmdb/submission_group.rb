class DRMDB::SubmissionGroup < DRMDB::Record
  self.table_name = "submission_group"

  belongs_to :submission, class_name: "DRMDB::Submission", foreign_key: "sub_id"

  has_many :accession_relations, class_name: "DRMDB::AccessionRelation", foreign_key: "grp_id", primary_key: "grp_id"
  has_many :ext_relations,       class_name: "DRMDB::ExtRelation",       foreign_key: "grp_id", primary_key: "grp_id"

  has_many :accession_entities, through: :accession_relations
  has_many :meta_entities,      through: :accession_relations
  has_many :ext_entities,       through: :ext_relations
  has_many :ext_permits,        through: :ext_relations

  class << self
    def instance_method_already_implemented?(method_name)
      return true if method_name == "valid?"
      super
    end
  end
end
