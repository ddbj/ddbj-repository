# Ask the object store whether it is there, so that somebody finds out.
#
# SeaweedFS has now died silently twice. The Kamal accessory has carried a
# `/status` healthcheck since the MinIO migration, but a healthcheck only
# decides whether to route traffic — it tells nobody. In June 2026 the
# master crash-looped for two weeks before a blob-writing importer
# surfaced it as a 100% failure rate; in July a container was OOM-killed
# and sat dead until an accession issuance happened to need the chain.
#
# Both times the storage was only missed by code that writes blobs, and
# neither time was that code running. This runs whether anything else
# does.
#
# `head_bucket` rather than a read of some known key: when the proxy has
# no container to route to it answers 404 for everything, which a missing
# object cannot be told apart from — but a missing *bucket* is a fault in
# its own right, so either answer is worth reporting.
class StorageHealthcheckJob < ApplicationJob
  # Deliberately not discarded. Reporting and swallowing would leave
  # SolidQueue recording a successful run, so Mission Control — the
  # operational view the team actually opens — would show nothing, and
  # the only channel would be a Sentry event that development has no DSN
  # for. A job whose whole purpose is that somebody finds out should be
  # visible in both places, so it reports and then fails.
  retry_on StandardError, attempts: 1 do |_job, error|
    Rails.error.report(error, handled: false, source: 'storage_healthcheck')

    raise error
  end

  # Asked once, briefly. The default S3 client waits 15s to connect, 60s
  # to read, and retries three times — so a store that black-holes rather
  # than refuses would hold a worker for minutes, every hour, against the
  # three threads that also run the migration and publish jobs.
  TIMEOUTS = {http_open_timeout: 5, http_read_timeout: 5, retry_limit: 0}.freeze

  def perform
    service = ActiveStorage::Blob.service

    # Only the S3-backed services can be asked this. Disk storage in
    # development is not a thing that goes away without being noticed.
    return unless service.respond_to?(:bucket)

    bucket = service.bucket

    self.class.probe_client(bucket.client.config).head_bucket(bucket: bucket.name)

    Rails.logger.info("[storage_healthcheck] #{bucket.name} reachable")
  end

  # The configured client with the waiting taken out. Its settings are
  # named rather than copied wholesale — `config.to_h` carries keys the
  # constructor refuses, and a probe that cannot be built would report a
  # fault in itself as a fault in the store.
  def self.probe_client(config)
    Aws::S3::Client.new(
      region:           config.region,
      credentials:      config.credentials,
      endpoint:         config.endpoint,
      force_path_style: config.force_path_style,
      **TIMEOUTS
    )
  end
end
