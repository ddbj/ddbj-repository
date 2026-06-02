module DDBJRecord
  module V3
    Analysis = Data.define(
      :accession,
      :alias,
      :title,
      :description,
      :analysis_type,
      :analysis_date,
      :files,
      :processing,
      :attributes
    )
  end
end
