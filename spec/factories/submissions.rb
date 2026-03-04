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

      submission.flatfile_na.attach(
        io:           Rails.root.join('spec/fixtures/files/flatfile/example.flat').open,
        filename:     'example_na.flat',
        content_type: 'text/plain'
      )

      submission.flatfile_aa.attach(
        io:           Rails.root.join('spec/fixtures/files/flatfile/example.flat').open,
        filename:     'example_aa.flat',
        content_type: 'text/plain'
      )
    end
  end
end
