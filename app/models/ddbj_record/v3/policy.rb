module DDBJRecord
  module V3
    Policy = Data.define(
      :accession,
      :alias,
      :title,
      :description,
      :dac_accession
    )
  end
end
