FactoryBot.define do
  factory :obj do
    _id  { Obj._ids.values.sample }
    file { Rack::Test::UploadedFile.new(StringIO.new(""), original_filename: "foo.txt") }
  end
end
