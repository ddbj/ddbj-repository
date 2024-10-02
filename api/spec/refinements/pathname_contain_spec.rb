require "rails_helper"

RSpec.describe PathnameContain do
  using PathnameContain

  example do
    base = Pathname.new("/base/dir")

    expect(base.contain?(Pathname.new("/base/dir/foo"))).to eq(true)
    expect(base.contain?(Pathname.new("/base/dir"))).to eq(true)
    expect(base.contain?(Pathname.new("/base/dir/."))).to eq(true)
    expect(base.contain?(Pathname.new("/base/dir/../dir"))).to eq(true)

    expect(base.contain?(Pathname.new("/base/foo"))).to eq(false)
    expect(base.contain?(Pathname.new("/base/dirfoo"))).to eq(false)
    expect(base.contain?(Pathname.new("/base/dir/../foo"))).to eq(false)
  end
end
