module DDBJRecord
  module V3
    Sample = Data.define(
      :accession,
      :alias,
      :title,
      :description,
      :package,
      :donor_id,
      :sample_group_type,
      :organism,
      :attributes
    )
  end
end
