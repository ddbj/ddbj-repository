# Handing over a file, once the route's own record has said the caller may
# have it.
#
# A redirect to a short-lived storage URL, not a proxy through this
# process. These are submission files and a genome assembly is measured in
# gigabytes; streaming those through Puma to avoid a five-minute signed
# URL is the wrong trade. The window is
# `ActiveStorage.service_urls_expire_in`.
#
# What this replaces is Active Storage's own `/rails/active_storage/blobs`
# route, which is disabled (`config.active_storage.draw_routes`). That
# route takes a signed blob id and nothing else, so the URL it mints is a
# bearer credential with no expiry and no owner: whoever holds it has the
# file, for ever, whatever has happened to their access since. Every path
# through here re-asks.
module AttachmentDownload
  extend ActiveSupport::Concern

  included do
    # What tells the Disk service which host to build its URLs against.
    # Active Storage's own controllers get it from here too; ours are not
    # its controllers, so they have to ask for it.
    include ActiveStorage::SetCurrent
  end

  private

  # Takes whatever the caller has in hand — a `has_one_attached` proxy, one
  # `ActiveStorage::Attachment` out of a `has_many`, or nothing at all —
  # and reduces it to the blob, which is the only thing storage needs.
  def redirect_to_attachment(attachment)
    blob = attachment.respond_to?(:blob) ? attachment.blob : attachment

    raise ActiveRecord::RecordNotFound unless blob

    # Never cached, and never stored. `expires_now` says `no-cache`,
    # which permits keeping the answer as long as it is revalidated —
    # but there is nothing to revalidate against here (no ETag, no
    # Last-Modified), and what the answer holds is a signed URL that
    # works for anyone. A second click has to come back here and be
    # asked about again: a membership revoked a minute ago must be a
    # download that stops, not one that stops in five minutes.
    no_store

    url = blob.url(disposition:)

    # A browser cannot put an `Authorization` header on an anchor, and
    # this API takes no cookies — so the web client asks for the address
    # instead of following the redirect, and navigates to it itself.
    # Everything else (curl, the bulk client, the admin screens) follows
    # the redirect as before.
    return render json: {url:} if params[:as] == 'url'

    redirect_to url, allow_other_host: true
  end

  # `inline` unless asked otherwise, matching Active Storage's own
  # default. Anything but the one recognised value is that default rather
  # than an error — a disposition is a preference, not an instruction.
  def disposition
    params[:disposition] == 'attachment' ? 'attachment' : 'inline'
  end
end
