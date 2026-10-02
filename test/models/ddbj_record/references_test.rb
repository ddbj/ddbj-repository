require 'test_helper'

class DDBJRecord::ReferencesTest < ActiveSupport::TestCase
  RECORD = {
    'experiments' => [
      {'alias' => 'e', 'accession' => 'DRX000001'},
      {'alias' => 'twin'},
      {'alias' => 'twin  '},
      {'alias' => 'only'}
    ]
  }.freeze

  def resolve(**) = DDBJRecord::References.resolve(RECORD, 'experiments', **)

  test 'an accession names its object, whatever else is said' do
    assert_same RECORD['experiments'][0], resolve(accession: 'DRX000001', name: 'only')
  end

  # As DRA::Converter writes them: spaced apart only, they are namesakes.
  test 'an alias names its object, and its position among namesakes says which' do
    assert_same RECORD['experiments'][3], resolve(name: 'only')
    assert_same RECORD['experiments'][2], resolve(name: 'twin', index: 1)
    assert_nil resolve(name: 'twin'), 'namesakes, without saying which'
    assert_nil resolve(name: 'none')
  end
end
