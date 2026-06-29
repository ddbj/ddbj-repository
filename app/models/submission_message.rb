# One message in the per-submission curator ↔ submitter thread.
#
# A submission carries a single chronological thread (per
# [[project-submission-messaging-design]]'s "1 submission = 1 thread"
# rule). `author_role` distinguishes who wrote it, NOT who can see it:
# both curators and the submission's owner can read every message.
#
# `read_at` is stamped when the OTHER party first observes the message
# (a curator-authored message gets stamped when the submitter opens the
# thread; a submitter-authored message gets stamped on any curator's
# admin show page view). Used to drive the "unread" badge on the
# submitter's home request list.
class SubmissionMessage < ApplicationRecord
  belongs_to :submission
  belongs_to :user

  AUTHOR_ROLES = %w[curator submitter].freeze

  # `suffix: :role` → `Model.curator_role` scope, `instance.curator_role?`
  # predicate. (Plain `suffix: true` would expand to `_author_role`,
  # giving the ugly `curator_author_role` instead.)
  #
  # `index_with(&:itself)` keeps the *string* form on a string column.
  # Passing the bare array form would have Rails store integer indices,
  # which the string `author_role` column would silently mangle.
  enum :author_role, AUTHOR_ROLES.index_with(&:itself), suffix: :role, validate: true

  validates :body, presence: true

  scope :chronological, -> { order(:created_at, :id) }
  scope :unread,        -> { where(read_at: nil) }
end
