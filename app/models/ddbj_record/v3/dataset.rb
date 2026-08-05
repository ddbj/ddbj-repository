module DDBJRecord
  module V3
    Dataset = Data.define(
      :accession,
      :alias,
      :title,
      :description,
      :dataset_types,
      :attributes,
      :runs,
      :analyses,
      :policy_accession
    )
  end
end
