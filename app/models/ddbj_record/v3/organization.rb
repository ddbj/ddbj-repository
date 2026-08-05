module DDBJRecord
  module V3
    Organization = Data.define(
      :name,
      :abbreviation,
      :url,
      :role,
      :type,
      :department,
      :address,
      :ror_id
    )
  end
end
