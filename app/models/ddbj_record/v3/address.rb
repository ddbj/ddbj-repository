module DDBJRecord
  module V3
    Address = Data.define(
      :country,
      :state,
      :city,
      :street,
      :postal_code
    )
  end
end
