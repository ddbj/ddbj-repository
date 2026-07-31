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

  # A service whose client is configured but whose head_bucket answers
  # with `error` — nil for a store that is simply there.
  def storage_answering(error)
    client = Class.new do
      define_method(:initialize) {|raises| @raises = raises }
      define_method(:head_bucket) {|**| raise @raises if @raises }
      define_method(:config) { nil }
    end.new(error)

    Struct.new(:bucket).new(Struct.new(:client, :name).new(client, 'uploads'))
  end

  def perform_against(service, &)
    StorageHealthcheckJob.stub(:probe_client, ->(_config) { service.bucket.client }) do
      ActiveStorage::Blob.stub(:service, service, &)
    end
  end

  # Reported AND failed. Swallowing it would leave SolidQueue recording a
  # successful run, so Mission Control — the view the team actually opens
  # — would show nothing, and development has no Sentry DSN at all.
  test 'an unreachable store is reported and fails the job' do
    refused = Seahorse::Client::NetworkingError.new(SocketError.new('Connection refused'))
    service = storage_answering(refused)

    reports = capture_error_reports {
      perform_against(service) do
        assert_raises(Seahorse::Client::NetworkingError) { StorageHealthcheckJob.perform_now }
      end
    }

    assert reports.any? { it.is_a?(Seahorse::Client::NetworkingError) },
           'a store nobody can reach has to reach somebody'
  end

  # A 404 for the bucket is what an unreachable store looks like through
  # kamal-proxy, which answers 404 for everything when it has no
  # container to route to — so it is a fault, not an absence.
  test 'a missing bucket is reported too' do
    service = storage_answering(Aws::S3::Errors::NotFound.new(nil, 'Not Found'))

    reports = capture_error_reports {
      perform_against(service) do
        assert_raises(Aws::S3::Errors::NotFound) { StorageHealthcheckJob.perform_now }
      end
    }

    assert reports.any? { it.is_a?(Aws::S3::Errors::NotFound) }
  end

  test 'a store that answers reports nothing' do
    service = storage_answering(nil)

    reports = capture_error_reports { perform_against(service) { StorageHealthcheckJob.perform_now } }

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
end
