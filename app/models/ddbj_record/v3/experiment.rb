module DDBJRecord
  module V3
    Experiment = Data.define(
      :accession,
      :alias,
      :title,
      :description,
      :library,
      :platform,
      :targeted_loci,
      :spot_descriptor,
      :processing,
      :attributes
    )
  end
end
