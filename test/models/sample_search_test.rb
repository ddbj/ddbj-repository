require 'test_helper'

class SampleSearchTest < ActiveSupport::TestCase
  setup do
    @relation = submissions(:biosample).samples
  end

  def search(params) = SampleSearch.new(@relation, params).scope

  test 'no params is no constraint' do
    assert_equal @relation.count, search({}).count
    refute SampleSearch.new(@relation, {}).active?
  end

  test 'the search term matches name, organism and accession' do
    samples(:second).update!(organism: 'soil metagenome')

    assert_equal [samples(:first)],  search(q: 'sample-1').to_a
    assert_equal [samples(:second)], search(q: 'soil').to_a
    assert_equal [samples(:first)],  search(q: 'SAMD00000001').to_a
  end

  # A curator pasting a sample name containing % or _ must not have it
  # read as a wildcard.
  test 'LIKE metacharacters in the search term are escaped' do
    samples(:first).update!(sample_name: '100%-complete')

    assert_equal [samples(:first)], search(q: '100%-complete').to_a
    assert_empty search(q: '%zzz%').to_a
  end

  test 'status and accession state filter independently' do
    assert_equal [samples(:first)],  search(status: 'private').to_a
    assert_equal [samples(:first)],  search(accession: 'issued').to_a
    assert_equal [samples(:second)], search(accession: 'not_issued').to_a
  end

  test 'the unassigned sentinel selects rows with no assignee' do
    samples(:first).update!(assignee: users(:bob))

    assert_equal [samples(:second)], search(assignee: '0').to_a
    assert_equal [samples(:first)],  search(assignee: users(:bob).id.to_s).to_a
    assert_equal 2,                  search(assignee: ['0', users(:bob).id.to_s]).count
  end

  test 'filters compose' do
    assert_empty search(q: 'sample-1', accession: 'not_issued').to_a
  end

  test 'an unknown accession state is ignored rather than emptying the list' do
    assert_equal @relation.count, search(accession: 'nonsense').count
  end

  test 'to_params round-trips the active filter for links and forms' do
    params = SampleSearch.new(@relation, {q: ' probe ', status: 'private', accession: 'issued'}).to_params

    assert_equal({q: 'probe', status: ['private'], accession: 'issued'}, params)
  end
end
