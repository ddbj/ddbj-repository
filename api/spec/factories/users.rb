FactoryBot.define do
  factory :user do
    sequence(:uid) { "user#{_1}" }

    first_name   { 'Alice' }
    last_name    { 'Liddell' }
    organization { 'Wonderland Inc.' }
    email        { 'test@example.com' }
  end
end
