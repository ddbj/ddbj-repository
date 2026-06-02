module DDBJRecord
  module V3
    Feature = Data.define(
      :alias,
      :type,
      :location,
      :sequence_id,
      :locus_tag_id,
      :source_tool,
      :qualifiers,
      :score,
      :phase,
      :parent_ids
    )
  end
end
