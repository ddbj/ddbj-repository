# Shared list filter for a column backed by an enum, for the API indexes.
#
# A value the server does not know is a client asking for something that
# cannot exist. Intersecting with the known set and dropping the filter
# when nothing survives answers that with the whole table — the one
# answer that is certainly wrong, and the one a script cannot tell from a
# real one. A reconciliation pass reading `?status[]=applied` after the
# enum had been renamed would have walked every request in the database
# believing each was applied.
#
# So: unknown values are refused. `phase` is deliberately not like this —
# it has a default, and an unrecognised value there falls through to it
# rather than 400-ing on a bookmarked URL.
#
# The admin indexes keep their own filters. Their contract is a checkbox
# group where "everything ticked" means no constraint, and a curator
# typing a bad value into their own URL is not the failure this guards
# against.
module EnumFilterable
  extend ActiveSupport::Concern

  # ActionController::BadRequest rather than a bare StandardError: Rails
  # already answers it with 400, and Sentry already leaves it alone. A
  # script looping on a stale filter value is a client mistake reported
  # to the client — turning each one into an error event would bury the
  # faults that are ours.
  class UnknownFilterValue < ActionController::BadRequest
    # The message names the value the caller sent and what was expected.
    include PublicError
  end

  # What of the client's input is quoted back. The parameter is not
  # necessarily the small list of strings it is supposed to be —
  # `?db[a]=x` arrives as a hash — and the message goes into a response
  # body and a log line.
  MAX_REPORTED       = 5
  MAX_REPORTED_LENGTH = 40

  private

  # Returns the scope unchanged when the filter is absent — the client
  # omits the parameter entirely rather than sending every value.
  def filter_by_enum(scope, column, raw, known)
    values = Array(raw).map(&:to_s).reject(&:blank?)
    return scope if values.empty?

    if (unknown = values - known).any?
      raise UnknownFilterValue,
            "Unknown #{column}: #{reportable(unknown)}. Valid values are #{known.join(', ')}."
    end

    scope.where(column => values)
  end

  def reportable(values)
    shown = values.take(MAX_REPORTED).map { it.truncate(MAX_REPORTED_LENGTH) }

    shown.join(', ') + (values.size > MAX_REPORTED ? ", and #{values.size - MAX_REPORTED} more" : '')
  end
end
