FactoryBot.define do
  factory :accession do
    sequence(:number)   { "ACC#{it.to_s.rjust(6, '0')}" }
    sequence(:entry_id) { "ENTRY#{it.to_s.rjust(6, '0')}" }
  end
end
