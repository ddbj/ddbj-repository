FactoryBot.define do
  factory :submission_request do
    db { 'JVar' }

    after :create do |request|
      create :obj, owner: request, _id: '_base', file: nil
    end
  end
end
