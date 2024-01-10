FactoryBot.define do
  factory :submission do
    validation { association(:validation, :valid) }
  end
end
