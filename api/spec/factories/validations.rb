FactoryBot.define do
  factory :validation do
    transient do
      validity { nil }
    end

    user

    db       { DB.map { _1[:id] }.sample }
    progress { 'waiting' }

    after :build do |validation|
      if validation.running? || validation.finished? || validation.canceled?
        validation.started_at = '2024-01-02' unless validation.started_at
      end

      if validation.finished? || validation.canceled?
        validation.finished_at = '2024-01-03' unless validation.finished_at
      end
    end

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
