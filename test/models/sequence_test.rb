require 'test_helper'

class SequenceTest < ActiveSupport::TestCase
  test 'allocate! generates sequential accession numbers' do
    assert_equal 'QP000001', Sequence.allocate!(:jpo_na, 1).last

    Sequence.find_by!(scope: 'jpo_na').update! next: 1000000

    assert_equal 'QQ000001', Sequence.allocate!(:jpo_na, 1).last
  end
end
