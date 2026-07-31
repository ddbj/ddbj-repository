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
  # Not retried. A retry would only delay the report, and the next run is
  # an hour away in any case.
  discard_on StandardError do |_job, error|
    Rails.error.report(error, handled: true, source: 'storage_healthcheck')
  end

  def perform
    service = ActiveStorage::Blob.service

    # Only the S3-backed services can be asked this. Disk storage in
    # development is not a thing that goes away without being noticed.
    return unless service.respond_to?(:bucket)

    service.bucket.client.head_bucket(bucket: service.bucket.name)

    Rails.logger.info("[storage_healthcheck] #{service.bucket.name} reachable")
  end
end
