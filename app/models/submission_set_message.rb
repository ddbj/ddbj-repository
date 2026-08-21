# One message in a set's thread — the conversation about the bundle
# rather than about any one submission in it.
#
# Everyone in the set reads and writes this one. The per-submission
# threads are not part of it: those are between one submitter and DDBJ,
# and reading somebody's submission through a shared set is not being
# party to what they have been asked about it (SetContents scopes the
# unread counts on the set page for the same reason).
#
# `author_role` is `member` rather than `submitter`. Here the other side
# of the conversation is a roster, and the message says which of them
# wrote it — `user` is shown, unlike the request thread where every
# submitter message is by definition the owner's.
#
# There is no `read_at` column. On a request thread that one timestamp
# works because there is exactly one submitter; a set has as many members
# as it has, so how far somebody has read is a fact about the person —
# SubmissionSetMember#last_read_at for members,
# SubmissionSetParticipant#last_read_at for curators.
class SubmissionSetMessage < ApplicationRecord
  # `set` is the word everywhere else — the class is SubmissionSet only
  # because Ruby owns the constant `Set`.
  # `touch: true` because both screens that list sets are ordered by when
  # the set was last touched, and a conversation is the only thing that
  # touches most of them. Without it a set renamed in March sorts above
  # one somebody wrote in this morning, and the queue's "oldest first"
  # would be oldest by rename.
  belongs_to :set, class_name: 'SubmissionSet', foreign_key: :submission_set_id, inverse_of: :messages, touch: true
  belongs_to :user

  # Same reasoning as the request thread's: the files this conversation
  # is about are submission files, and both sides upload straight to
  # storage, so nothing here is bounded by a request body.
  has_many_attached :files

  AUTHOR_ROLES = %w[curator member].freeze

  # Hash form on a string column — the array form stores integer indices
  # and mangles them silently. `suffix: :role` gives `curator_role?`
  # rather than the unreadable `curator_author_role?`.
  enum :author_role, AUTHOR_ROLES.index_with(&:itself), suffix: :role, validate: true

  # "Here is the corrected file" needs no prose; nothing at all is a
  # misfire, and both sides refuse it before they get here.
  validates :body, presence: true, unless: -> { files.attached? }

  scope :chronological, -> { order(:created_at, :id) }

  # Both scopes below compare `(created_at, id)` rather than `created_at`
  # alone, matching the order the thread is read in. On `created_at` a
  # question and its answer written in the same microsecond — reachable
  # for seeded or imported rows — leave the thread waiting on both sides
  # at once, while the screen renders them as asked-then-answered.

  # Member messages nobody on the curator side has answered — the same
  # collective rule the request thread uses, for the same reason:
  # answering is the work, so it settles the thread for every curator.
  scope :unanswered, -> {
    member_role.where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM submission_set_messages later
        WHERE later.submission_set_id = submission_set_messages.submission_set_id
          AND later.author_role = 'curator'
          AND (later.created_at, later.id) > (submission_set_messages.created_at, submission_set_messages.id)
      )
    SQL
  }

  # Curator messages the set has not answered. The mirror of the above,
  # and what puts "waiting on us" on a member's screen — collective for
  # the same reason: a colleague answering answers for the set.
  scope :unanswered_by_members, -> {
    curator_role.where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM submission_set_messages later
        WHERE later.submission_set_id = submission_set_messages.submission_set_id
          AND later.author_role = 'member'
          AND (later.created_at, later.id) > (submission_set_messages.created_at, submission_set_messages.id)
      )
    SQL
  }
end
