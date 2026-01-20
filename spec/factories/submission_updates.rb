FactoryBot.define do
  factory :submission_update do
    transient do
      user { build(:user) }
    end

    submission { association(:submission, user:) }

    after :build do |update|
      update.ddbj_record.attach(
        io:           Rails.root.join('spec/fixtures/files/ddbj_record/example.json').open,
        filename:     'example.json',
        content_type: 'application/json'
      )
    end
  end
end
