module DDBJRecord
  module V3
    Entry = Data.define(
      :accession,
      :alias,
      :name,
      :type,
      :topology,
      :division,
      :sequence,
      :comments,
      :source_features
    )
  end
end
