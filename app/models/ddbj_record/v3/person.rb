module DDBJRecord
  module V3
    Person = Data.define(
      :first,
      :last,
      :email,
      :orcid,
      :organization,
      :role
    )
  end
end
