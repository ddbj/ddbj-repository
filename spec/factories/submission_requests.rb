FactoryBot.define do
  factory :submission_request do
    after :build do |request|
      request.ddbj_record.attach(
        io:           Rails.root.join('spec/fixtures/files/ddbj_record/example.json').open,
        filename:     'example.json',
        content_type: 'application/json'
      )
    end
  end
end
