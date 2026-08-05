module DDBJRecord
  module V3
    Project = Data.define(
      :accession,
      :alias,
      :name,
      :title,
      :description,
      :project_type,
      :umbrella_subtype,
      :study_types,
      :organism,
      :publications,
      :grants,
      :keywords,
      :relevance,
      :locus_tag_prefix,
      :target,
      :attributes
    )
  end
end
