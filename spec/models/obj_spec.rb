require "rails_helper"

RSpec.describe Obj, type: :model do
  example "path must be unique in validation" do
    validation = build(:validation, objs: [
      build(:obj, _id: "BioProject", file: uploaded_file(name: "dup.txt")),
      build(:obj, _id: "BioSample",  file: uploaded_file(name: "dup.txt"))
    ])

    expect(validation).to be_invalid
  end
end
