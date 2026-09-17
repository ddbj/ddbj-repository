#!/bin/sh
set -eu

# Iceberg and Lance are catalogs SeaweedFS 4.47 starts beside S3 unless told
# not to. Nothing here uses them, and a listener nobody uses is one more thing
# to answer on.
weed server -s3 \
  -s3.port=8333 \
  -s3.port.iceberg=0 \
  -s3.port.lance=0 \
  -s3.config=/etc/seaweedfs/s3.json \
  -s3.allowedOrigins='*' \
  -dir=/data \
  -volume.max=0 &
server=$!

# This script is PID 1, and a shell does not pass a stop on to its children:
# without the trap the server was never told to stop, and was SIGKILLed while
# running once `docker stop` gave up waiting.
trap 'kill -TERM $server 2>/dev/null' TERM INT

# What has to wait for the server runs beside it, so this script only ever
# waits on the server itself. Waiting here instead held a stop that arrived
# during startup until Docker's timeout ran out, and left the container up,
# polling, when the server died before it was ready.
#
# A bucket that could not be created does not stop the container from here;
# StorageHealthcheckJob asks for the bucket every hour and reports its absence.
(
  until curl -sf http://localhost:8333/status >/dev/null 2>&1; do
    sleep 0.5
  done

  # Only when it is missing. `s3.bucket.create` on a bucket that exists
  # replaces its entry, and with it whatever is configured on the bucket
  # (owner, versioning, CORS, lifecycle) — on every boot. It goes through the
  # shell, which talks to the master, because the S3 API answers nobody without
  # credentials. `timeout` because the shell waits for ever on a master it
  # cannot reach.
  if ! echo 's3.bucket.list' | timeout 60 weed shell -master=localhost:9333 | grep -qF "$(printf '  uploads\t')"; then
    echo 's3.bucket.create -name uploads' | timeout 60 weed shell -master=localhost:9333
  fi
) &

# No sweep of abandoned multipart uploads. `s3.clean.uploads` — and S3's own
# AbortMultipartUpload — delete the chunks of a *completed* object when its
# upload directory survived completion, which a stop between the commit and the
# cleanup is enough to cause; the object then reads fine until a vacuum and not
# after. https://github.com/seaweedfs/seaweedfs/issues/10663
#
# How the server ended is how the container ends, so a crash still shows as
# one. The first wait returns as soon as a signal arrives, while the trap is
# only asking the server to stop; if it is still there, wait for it to finish.
status=0
wait $server || status=$?

if kill -0 $server 2>/dev/null; then
  status=0
  wait $server || status=$?
fi

exit $status
