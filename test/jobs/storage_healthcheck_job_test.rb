require 'test_helper'

# The job exists so that a dead object store reaches a person. Its only
# interesting behaviour is what it does when the store is not there.
class StorageHealthcheckJobTest < ActiveJob::TestCase
  def capture_error_reports
    reports    = []
    subscriber = Class.new { define_method(:report) {|error, **| reports << error } }.new

    Rails.error.subscribe(subscriber)

    begin
      yield
    ensure
      Rails.error.unsubscribe(subscriber)
    end

    reports
  end

  test 'an unreachable store is reported rather than swallowed' do
    refused = Seahorse::Client::NetworkingError.new(SocketError.new('Connection refused'))

    reports = capture_error_reports {
      ActiveStorage::Blob.stub(:service, storage_answering(refused)) { StorageHealthcheckJob.perform_now }
    }

    assert reports.any? { it.is_a?(Seahorse::Client::NetworkingError) },
           'a store nobody can reach has to reach somebody'
  end

  # A 404 for the bucket is what an unreachable store looks like through
  # kamal-proxy, which answers 404 for everything when it has no
  # container to route to — so it is a fault, not an absence.
  test 'a missing bucket is reported too' do
    reports = capture_error_reports {
      ActiveStorage::Blob.stub(:service, storage_answering(Aws::S3::Errors::NotFound.new(nil, 'Not Found'))) do
        StorageHealthcheckJob.perform_now
      end
    }

    assert reports.any? { it.is_a?(Aws::S3::Errors::NotFound) }
  end

  test 'a store that answers reports nothing' do
    reports = capture_error_reports {
      ActiveStorage::Blob.stub(:service, storage_answering(nil)) { StorageHealthcheckJob.perform_now }
    }

    assert_empty reports
  end

  # Disk storage in development has no bucket to ask about, and is not a
  # thing that goes away without somebody noticing.
  test 'a service with no bucket is left alone' do
    reports = capture_error_reports {
      ActiveStorage::Blob.stub(:service, Object.new) { StorageHealthcheckJob.perform_now }
    }

    assert_empty reports
  end

  private

  def storage_answering(error)
    client = Class.new do
      define_method(:initialize) {|raises| @raises = raises }
      define_method(:head_bucket) {|**| raise @raises if @raises }
    end.new(error)

    bucket = Struct.new(:client, :name).new(client, 'uploads')

    Struct.new(:bucket).new(bucket)
  end
end
