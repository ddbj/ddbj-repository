FactoryBot.define do
  factory :request do
    user

    purpose { Request.purposes.values.sample }
    db      { DB.map { _1[:id] }.sample }
    status  { 'waiting' }

    after :create do |request|
      create :obj, request:, _id: '_base'
    end
  end
end
