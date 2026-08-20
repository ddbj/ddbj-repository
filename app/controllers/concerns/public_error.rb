# Whether an exception's message belongs in the response body.
#
# Include this in an error class whose message is a sentence written for
# whoever will read it — "Only the owner can rename a set", not
# "PG::UniqueViolation: ERROR: duplicate key value violates …".
#
# Rails' own messages are written for us. Some of them recite the query
# that produced them: `find_by!` on a scope names every column of the
# WHERE clause, which on an unauthenticated endpoint hands out the
# schema to anybody who passes a wrong token.
module PublicError
  # The `find(id)` form names only what the caller asked for and is
  # genuinely useful in an API. The relation form names our columns.
  WHERE_CLAUSE = '[WHERE'

  def self.message_for(exception, fallback:)
    # Rails' default `message` is the class name when nothing was given.
    return fallback if exception.message == exception.class.to_s
    return exception.message if exception.is_a?(PublicError)

    # "Validation failed: Email is already a member of this set." Every
    # validation in this application is a rule somebody typing into a form
    # is meant to read, and the message is assembled from the attribute
    # name and the sentence the model wrote. Withholding it turns the two
    # most likely answers on any form — already taken, cannot be blank —
    # into a status word.
    return exception.message if exception.is_a?(ActiveRecord::RecordInvalid)

    return exception.message if exception.is_a?(ActiveRecord::RecordNotFound) && exception.message.exclude?(WHERE_CLAUSE)

    fallback
  end
end
