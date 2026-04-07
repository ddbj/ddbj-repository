require 'test_helper'

class PathnameContainTest < ActiveSupport::TestCase
  using PathnameContain

  test 'contain? returns true for contained paths' do
    base = Pathname.new('/base/dir')

    assert base.contain?(Pathname.new('/base/dir/foo'))
    assert base.contain?(Pathname.new('/base/dir'))
    assert base.contain?(Pathname.new('/base/dir/.'))
    assert base.contain?(Pathname.new('/base/dir/../dir'))
  end

  test 'contain? returns false for non-contained paths' do
    base = Pathname.new('/base/dir')

    refute base.contain?(Pathname.new('/base/foo'))
    refute base.contain?(Pathname.new('/base/dirfoo'))
    refute base.contain?(Pathname.new('/base/dir/../foo'))
  end
end
