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

  test 'what does not read as a time is refused, not taken for none' do
    assert_raises(ArgumentError) { DataMigration::DwayDefaults.time('infinity') }
  end

  # D-way's dist_date does not move on the way out of public, and a row made
  # public before D-way kept dates has none; its last change stands in.
  test 'when D-way last published a row, as far as it can say' do
    dist     = Time.zone.local(2020, 1, 1)
    modified = Time.zone.local(2024, 1, 1)
    at       = ->(**kw) { DataMigration::DwayDefaults.last_published_at(release: dist, dist:, modified:, **kw) }

    assert_equal dist,     at.(public: true)
    assert_equal modified, at.(public: false), 'left public after its last distribution'
    assert_equal modified, DataMigration::DwayDefaults.last_published_at(public: true, release: nil, dist: nil, modified:), 'public before D-way kept dates'
    assert_nil DataMigration::DwayDefaults.last_published_at(public: false, release: nil, dist: nil, modified:), 'never public'
  end
end
