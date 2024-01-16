FactoryBot.define do
  factory :validation do
    user

    db       { DB.map { _1[:id] }.sample }
    progress { 'waiting' }
    objs     { [build(:obj, _id: '_base', file: nil)] }

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
