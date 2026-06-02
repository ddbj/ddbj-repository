module DDBJRecord
  module V3
    Sequences = Data.define(
      :seq_prefix,
      :common_source,
      :entries,
      :structured_comments,
      :attributes
    )
  end
end
