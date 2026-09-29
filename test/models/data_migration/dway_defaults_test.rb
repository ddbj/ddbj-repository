require 'test_helper'

class DataMigration::DwayDefaultsTest < ActiveSupport::TestCase
  # D-way keeps Tokyo's wall clock without a zone. Taken for UTC it would be
  # nine hours late wherever it is written without conversion.
  test 'a D-way timestamp is Tokyo time, whatever zone the process is in' do
    Time.use_zone('UTC') do
      assert_equal Time.utc(2014, 3, 20, 1, 32, 3.806r), DataMigration::DwayDefaults.time('2014-03-20 10:32:03.806')
    end

    assert_nil DataMigration::DwayDefaults.time(nil)
  end
end
