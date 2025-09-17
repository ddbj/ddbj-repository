FactoryBot.define do
  factory :accession do
    sequence(:number)   { "ACC_#{it.to_s.rjust(6, '0')}" }
    sequence(:entry_id) { "ENTRY_#{it.to_s.rjust(6, '0')}" }
  end
end
