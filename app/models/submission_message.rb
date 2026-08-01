# One message in the per-request curator ↔ submitter thread.
#
# A request carries a single chronological thread (per
# [[project-submission-messaging-design]]'s "1 thread" rule). The
# thread hangs off the SubmissionRequest — not the Submission — so the
# conversation can start before Apply, when no Submission exists yet.
# `author_role` distinguishes who wrote it, NOT who can see it: both
# curators and the request's owner can read every message.
#
# `read_at` carries ONE direction now: a curator-authored message is
# stamped when the submitter deals with it — by replying, or by saying
# there is nothing to reply to. It is never stamped on a submitter's
# message, because "read" in that direction is not a fact about the
# message at all: it is a fact about each curator, and lives on their
# subscription (SubmissionRequestParticipant#last_read_at). A colleague
# reading a thread is not this curator having read it.
class SubmissionMessage < ApplicationRecord
  belongs_to :submission_request
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

  # Curators copied in on this message. Subscribing them is what makes it
  # do anything later; this is what makes the thread say it happened.
  def cc_users = User.where(id: cc_user_ids).order(:uid)

  # Submitter messages nobody has answered — no curator has posted since.
  #
  # This is what "waiting on a curator" means, and it is deliberately
  # collective: a colleague ANSWERING is the work being done, so it
  # settles the thread for everyone. A colleague merely reading is not,
  # which is why reading writes nothing at all now. Each curator can
  # narrow this further with their own marker (see
  # SubmissionRequestParticipant#last_read_at) without speaking for the
  # rest.
  scope :unanswered, -> {
    submitter_role.where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM submission_messages later
        WHERE later.submission_request_id = submission_messages.submission_request_id
          AND later.author_role = 'curator'
          AND later.created_at > submission_messages.created_at
      )
    SQL
  }
end
