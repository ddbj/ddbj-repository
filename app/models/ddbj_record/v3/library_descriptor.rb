module DDBJRecord
  module V3
    LibraryDescriptor = Data.define(
      :name,
      :strategy,
      :source,
      :selection,
      :layout,
      :construction_protocol,
      :nominal_length,
      :nominal_sdev
    )
  end
end
