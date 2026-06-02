module DDBJRecord
  module V3
    Publication = Data.define(
      :title,
      :pubmed_id,
      :doi,
      :status,
      :date,
      :journal,
      :volume,
      :issue,
      :pages_from,
      :pages_to,
      :authors,
      :consortiums
    )
  end
end
