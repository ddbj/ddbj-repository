# "The object store is not answering", as distinct from "that object is
# not there".
#
# Usable directly in a rescue clause — `rescue StorageFailure => e` — via
# the `===` below, so the two places that need to tell these apart do it
# by the same rule rather than by two lists that drift.
#
# The distinction matters because the wrong reading is expensive both
# ways. A missing object is a fact about one record and the caller should
# carry on; an unreachable store is a fact about every record, and
# carrying on means writing 15,000 rows of the same error, or worse,
# treating every submission's history as empty.
module StorageFailure
  # `Aws::S3::Errors::ServiceError` rather than a list of the ones we
  # have hit: a rotated credential answers 403 (Forbidden /
  # SignatureDoesNotMatch — see the July 2026 rotation), a sick store
  # answers 5xx, and a proxy with nothing to route to answers 404. All
  # of them mean the same thing to a caller, and enumerating them is how
  # the next one gets missed.
  #
  # This does NOT catch a genuinely absent object: ActiveStorage converts
  # `NoSuchKey` into `ActiveStorage::FileNotFoundError` before it gets
  # here, which is exactly the per-record fact that should not stop a
  # sweep.
  ERRORS = [
    Aws::S3::Errors::ServiceError,
    Seahorse::Client::NetworkingError
  ].freeze

  # Walks the cause chain, because the failure rarely arrives bare.
  # Submission::MaterialisationFailed wraps whatever stopped the replay,
  # and Ruby records the original as `cause` when one exception is raised
  # while handling another — so this asks "was storage behind this",
  # which is the question, rather than "is this literally an S3 error".
  def self.===(error)
    while error
      return true if ERRORS.any? { error.is_a?(it) }

      error = error.cause
    end

    false
  end
end
