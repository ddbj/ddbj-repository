# What a client sends when it has already put the bytes in storage.
#
# Both sides of both conversations upload directly and then post the
# signed ids, so all four message endpoints receive the same shape and
# have to be equally careful with it: a malformed one (`files[a]=b`
# arrives as Parameters rather than an Array) would otherwise reach the
# model write and come back as a 500.
#
# An id that fails verification is a bad request rather than a fault —
# see config/initializers/rambulance.rb, which maps the signature error
# so that stays true past this point.
module AttachmentSignedIds
  extend ActiveSupport::Concern

  private

  def signed_ids(raw)
    return [] unless raw.is_a?(Array)

    raw.compact_blank.filter_map { it if it.is_a?(String) }
  end
end
