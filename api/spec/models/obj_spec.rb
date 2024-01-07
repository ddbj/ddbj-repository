require 'rails_helper'

RSpec.describe Obj, type: :model do
  example 'path must be unique in request' do
    request = build(:request, objs: [
      build(:obj, _id: 'Foo', file: uploaded_file(name: 'dup.txt')),
      build(:obj, _id: 'Bar', file: uploaded_file(name: 'dup.txt'))
    ])

    expect(request).to be_invalid
  end
end
