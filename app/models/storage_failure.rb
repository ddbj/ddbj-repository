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
  # That includes an object that is genuinely absent. ActiveStorage
  # converts `NoSuchKey` into `ActiveStorage::FileNotFoundError` inside a
  # `rescue`, so the original survives as `cause` and the walk below finds
  # it. That is deliberate: from here "the patch blobs of this chain are
  # gone" cannot be told from "the store lost them", and reading it as a
  # per-record absence lets a sweep treat every chain as empty and rebuild
  # the corpus from D-way. Stopping costs one wasted run.
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
