require 'test_helper'

class SampleTest < ActiveSupport::TestCase
  test 'sample_name presence required' do
    sample = Sample.new(submission: submissions(:biosample))

    assert_not sample.valid?
    assert_includes sample.errors[:sample_name], "can't be blank"

    sample.sample_name = 's1'
    assert sample.valid?
  end

  test 'accession format requires SAMD\d+' do
    sample = Sample.new(submission: submissions(:biosample), sample_name: 's1')

    sample.accession = 'SAMD01921306'
    assert sample.valid?

    sample.accession = 'SAMN01234567'
    assert_not sample.valid?

    sample.accession = nil
    assert sample.valid?
  end

  test 'release_type enum accepts nil and listed values' do
    sample = samples(:first)

    sample.release_type = :hold
    assert sample.valid?

    sample.release_type = :release
    assert sample.valid?

    sample.release_type = nil
    assert sample.valid?
  end

  test 'status accepts every Lifecycleable value' do
    sample = samples(:first)

    Sample.statuses.each_key do |name|
      sample.status = name
      assert sample.valid?, "Expected status #{name} to be valid"
    end
  end

  test 'assignee_must_be_admin rejects non-admin users' do
    sample = samples(:first)

    sample.assignee = users(:alice)
    assert_not sample.valid?

    sample.assignee = users(:bob)
    assert sample.valid?
  end
end
