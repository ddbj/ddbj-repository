module DDBJRecord
  module V3
    Root = Data.define(
      :schema_version,
      :provenance,
      :submission,
      :project,
      :samples,
      :experiments,
      :runs,
      :analyses,
      :sequences,
      :features,
      :assembly,
      :datasets,
      :relations,
      :access_control
    )
  end
end
