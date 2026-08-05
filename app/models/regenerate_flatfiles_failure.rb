# One submission a regeneration run could not rebuild, and why.
#
# Kept so the reason can be read on the screen that reports the run. The
# alternative — "see Jobs for failure details" — sends a curator to a
# queue browser to read a backtrace, which is a developer's tool showing
# a developer's view of a question they asked as "which records are
# stale?".
class RegenerateFlatfilesFailure < ApplicationRecord
  belongs_to :run, class_name: 'RegenerateFlatfilesRun'

  # Optional, because the two interesting failures are a submission
  # destroyed between enqueue and execution and one destroyed since. The
  # label is what the row is read by, so it carries the name instead.
  belongs_to :submission, optional: true

  validates :label,   presence: true
  validates :message, presence: true
end
