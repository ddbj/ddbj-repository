FactoryBot.define do
  factory :submitterdb_login, class: 'SubmitterDB::Login' do
    password { 'password' }
  end
end
