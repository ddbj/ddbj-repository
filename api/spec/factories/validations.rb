FactoryBot.define do
  factory :validation do
    transient do
      validity { nil }
    end

    user

    db       { DB.map { _1[:id] }.sample }
    progress { 'waiting' }

    after :create do |validation, evaluator|
      create :obj, validation:, _id: '_base', file: nil, validity: evaluator.validity
    end

    trait :valid do
      validity    { 'valid' }
      progress    { 'finished' }
      finished_at { Time.current }
    end
  end
end
