FactoryBot.define do
  factory :validation do
    user

    db       { DB.map { _1[:id] }.sample }
    progress { 'waiting' }

    after :create do |validation|
      create :obj, validation:, _id: '_base', file: nil
    end

    trait :valid do
      progress    { 'finished' }
      finished_at { Time.current }

      after :create do |validation|
        validation.objs.each do |obj|
          obj.validity_valid! unless obj.validity
        end
      end
    end
  end
end
