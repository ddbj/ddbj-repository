# One submission a regeneration run could not rebuild, and why.
#
# Kept so the reason can be read on the screen that reports the run. The
# alternative — "see Jobs for failure details" — sends a curator to a
# queue browser to read a backtrace, which is a developer's tool showing
# a developer's view of a question they asked as "which records are
# stale?".
class RegenerateFlatfilesFailure < ApplicationRecord
  belongs_to :run,        class_name: 'RegenerateFlatfilesRun'
  belongs_to :submission

  validates :message, presence: true

  # What the curator recognises the row by. Falls back to the submission
  # id only when there is nothing published to name it with.
  def display_label = label.presence || "submission ##{submission_id}"
end
