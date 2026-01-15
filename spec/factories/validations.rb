FactoryBot.define do
  factory :validation do
    after :build do |validation|
      if validation.finished? || validation.canceled?
        validation.finished_at = '2024-01-03' unless validation.finished_at
      end
    end

    trait :valid do
      progress    { 'finished' }
      finished_at { Time.current }
    end
  end
end
