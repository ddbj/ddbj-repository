FactoryBot.define do
  factory :user do
    sequence(:uid) { "user#{_1}" }
  end
end
