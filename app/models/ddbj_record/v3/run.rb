module DDBJRecord
  module V3
    Run = Data.define(
      :accession,
      :alias,
      :title,
      :run_date,
      :data_type,
      :files,
      :attributes
    )
  end
end
