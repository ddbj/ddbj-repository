module DDBJRecord
  module V3
    Assembly = Data.define(
      :accession,
      :alias,
      :name,
      :organism,
      :level,
      :scaffold_count,
      :total_length,
      :n50,
      :submission_category,
      :attributes
    )
  end
end
