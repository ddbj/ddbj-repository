FactoryBot.define do
  factory :submission do
    transient do
      user { build(:user) }
    end

    request { association(:submission_request, user:) }

    after :build do |submission|
      submission.ddbj_record.attach(
        io:           Rails.root.join('spec/fixtures/files/ddbj_record/example.json').open,
        filename:     'example.json',
        content_type: 'application/json'
      )
    end
  end
end
