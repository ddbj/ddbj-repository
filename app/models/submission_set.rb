# Submissions that belong together, and the people they belong to.
#
# Named after the submissions rather than after the people on purpose. A
# lab is a group; bundling submissions at the granularity of a lab has no
# use. What is worth bundling is a set of submissions that mean something
# together, whatever granularity that turns out to be — and the people
# fall out of it, rather than the set being a picture of an organisation.
#
# Two axes, and they are separate. SubmissionSetMember is who is in it;
# SubmissionSetInclusion is what is in it. Being a member does not put
# your submissions anywhere, and putting a submission in does not stop
# being your call — each member adds and removes their own.
#
# **Adding a submission is the whole permission story.** There is no
# other way a member comes to read somebody else's submission, no
# per-submission grant to keep in step, and nothing to reconcile when a
# person leaves: taking them off the roster takes their submissions with
# them, because the permission was never anywhere else.
class SubmissionSet < ApplicationRecord
  # Whoever created it. Not a role with powers over the work — every
  # member invites, and every member manages their own submissions —
  # only over the set as an object: renaming it and deleting it.
  belongs_to :owner, class_name: 'User'

  has_many :members, -> { ordered }, class_name: 'SubmissionSetMember', inverse_of: :set, dependent: :destroy

  # Accepted members only. A `through` association joins, so a row whose
  # invitation is still out has no user to join to and simply is not
  # here — which is what every caller asking "who is in this set"
  # means.
  has_many :users, through: :members

  has_many :inclusions, class_name: 'SubmissionSetInclusion', inverse_of: :set, dependent: :destroy
  has_many :submission_requests, through: :inclusions

  # The set's own conversation — see SubmissionSetMessage for why it is a
  # thread of its own rather than a message copied into the submissions'.
  has_many :messages, -> { chronological }, class_name: 'SubmissionSetMessage', inverse_of: :set, dependent: :destroy

  # Curators who have worked in this thread. Members are not here: the
  # roster is what makes the thread theirs.
  has_many :participations, class_name: 'SubmissionSetParticipant', inverse_of: :set, dependent: :destroy

  has_many :followers, -> { merge(SubmissionSetParticipant.subscribed) },
           through: :participations, source: :user

  # Who is answering the conversation. Only that: a set has no state to
  # move through, and nothing to hand over but the thread.
  belongs_to :assignee, class_name: 'User', optional: true

  validates :name, presence: true, length: {maximum: 200}

  # The creator is on the roster from the start. A set nobody is in
  # would have no one to invite the first member, and every rule below
  # that says "members can" would have nothing to say about the person
  # who just made it.
  after_create do |set|
    set.members.create!(user: set.owner, invited_by: set.owner, joined_at: Time.current)
  end

  # Sets this person is actually in. Outstanding invitations are not
  # membership: nothing is shared with somebody who has not walked
  # through the link yet.
  scope :joined_by, ->(user) { where(id: SubmissionSetMember.joined.where(user_id: user.id).select(:submission_set_id)) }

  # Sets a curator is following. The set-axis twin of
  # SubmissionRequest.involving.
  scope :followed_by, ->(user) {
    where(id: SubmissionSetParticipant.subscribed.where(user_id: user.id).select(:submission_set_id))
  }

  scope :assigned_to, ->(user) { where(assignee_id: user.id) }
  scope :unassigned,  -> { where(assignee_id: nil) }

  # Nobody has claimed it and nobody is listening — the same two
  # conditions the request axis uses, for the same reason: a set that
  # somebody stopped following is nobody's again, which is exactly what
  # this section is for.
  scope :unclaimed, -> {
    unassigned.where.not(id: SubmissionSetParticipant.subscribed.select(:submission_set_id))
  }

  # Sets whose thread is waiting on the curator side: a member has
  # written and no curator has written since.
  #
  # Given a curator it narrows to what they have not put aside
  # themselves, so one of them dismissing a thread does not speak for the
  # others — the same shape as MyQueue.unread_messages, one axis over.
  scope :needing_curator, ->(user = nil) { where(id: unread_curator_messages(user).select(:submission_set_id)) }

  def self.unread_curator_messages(user)
    return SubmissionSetMessage.unanswered unless user

    join = SubmissionSetMessage.sanitize_sql_array([<<~SQL.squish, user_id: user.id])
      LEFT JOIN submission_set_participants
        ON submission_set_participants.submission_set_id = submission_set_messages.submission_set_id
       AND submission_set_participants.user_id = :user_id
    SQL

    SubmissionSetMessage
      .unanswered
      .joins(join)
      .where('submission_set_participants.last_read_at IS NULL OR submission_set_messages.created_at > submission_set_participants.last_read_at')
  end

  # Sets whose thread is waiting on THIS member: a curator has written,
  # nobody in the set has answered, and this person has not marked it
  # read. The mirror of `needing_curator`, and the number the nav badge
  # carries so a member does not have to be on the sets page to know.
  scope :waiting_on_member, ->(user) {
    joined_by(user).where(id: unread_member_messages(user).select(:submission_set_id))
  }

  def self.unread_member_messages(user)
    join = SubmissionSetMessage.sanitize_sql_array([<<~SQL.squish, user_id: user.id])
      INNER JOIN submission_set_members
        ON submission_set_members.submission_set_id = submission_set_messages.submission_set_id
       AND submission_set_members.user_id = :user_id
    SQL

    SubmissionSetMessage
      .unanswered_by_members
      .joins(join)
      .where('submission_set_members.last_read_at IS NULL OR submission_set_messages.created_at > submission_set_members.last_read_at')
  end

  # Since when a set has been waiting on a curator — the oldest message
  # no curator has answered.
  #
  # NOT `updated_at`. That moves for a rename as readily as for a
  # message, so a five-day-old question sorts as new the moment somebody
  # touches the set, and the queue's promise of "oldest first" quietly
  # becomes "oldest by whatever last happened".
  def self.waiting_since(ids)
    return {} if Array(ids).empty?

    SubmissionSetMessage.unanswered.where(submission_set_id: ids).group(:submission_set_id).minimum(:created_at)
  end

  # The same value as a sort key, for the queue. A correlated subquery
  # rather than a join so the scope composes with the rest.
  scope :by_longest_waiting, -> {
    order(Arel.sql(<<~SQL.squish))
      (SELECT MIN(m.created_at) FROM submission_set_messages m
        WHERE m.submission_set_id = submission_sets.id
          AND m.author_role = 'member'
          AND NOT EXISTS (
            SELECT 1 FROM submission_set_messages later
            WHERE later.submission_set_id = m.submission_set_id
              AND later.author_role = 'curator'
              AND (later.created_at, later.id) > (m.created_at, m.id)
          )) ASC NULLS LAST
    SQL
  }

  # Who already holds the submissions in each set — the assignees, not
  # the owners.
  #
  # A question about a whole bundle is usually answered by whoever is
  # already curating most of it, and when that is split between people,
  # the split is the thing worth seeing: it is the difference between
  # "this is obviously mine" and "somebody has to agree who takes it".
  # `nil` is unassigned, which is a real answer rather than a gap.
  #
  # One grouped query for the whole page. {set_id => {assignee_id => n}}.
  def self.assignee_counts(ids)
    return {} if Array(ids).empty?

    SubmissionSetInclusion
      .where(submission_set_id: ids)
      .joins(:submission_request)
      .group(:submission_set_id, 'submission_requests.assignee_id')
      .count
      .each_with_object({}) {|((set_id, assignee_id), count), acc|
        (acc[set_id] ||= {})[assignee_id] = count
      }
  end

  # The three integers every list of sets prints, counted in SQL for the
  # whole page. There is no ceiling on what a set holds, and these must
  # not be what loads it.
  def self.counts_for(ids)
    {
      members:     SubmissionSetMember.joined.where(submission_set_id: ids).group(:submission_set_id).count,
      invited:     SubmissionSetMember.pending.where(submission_set_id: ids).group(:submission_set_id).count,
      submissions: SubmissionSetInclusion.where(submission_set_id: ids).group(:submission_set_id).count
    }
  end

  # What is waiting on one member, and on one curator, across a page of
  # sets. Two conditions in each, and they are different in kind: the
  # thread's own state — answered or not, which is collective because
  # answering is the work — and this person's marker, which is theirs
  # alone.
  def self.member_unread_counts(user, ids)
    return {} if user.nil? || Array(ids).empty?

    unread_member_messages(user).where(submission_set_id: ids).group(:submission_set_id).count
  end

  def self.curator_unread_counts(user, ids)
    return {} if user.nil? || Array(ids).empty?

    unread_curator_messages(user).where(submission_set_id: ids).group(:submission_set_id).count
  end

  def member?(user)
    return false unless user

    members.joined.exists?(user_id: user.id)
  end

  def owned_by?(user) = user && owner_id == user.id

  # Empty of everything but the owner. A set with somebody else's
  # submission in it is not the owner's to remove out from under them,
  # and a set with other people in it is not theirs to dissolve — so
  # the two get taken out first, by the people they belong to.
  #
  # An invitation nobody has walked through counts as somebody. Deleting
  # the set would kill a link that is sitting in a mailbox, and would
  # do it silently; taking the invitation back is a thing the owner can
  # see and undo.
  def deletable? = inclusions.none? && messages.none? && members.where.not(id: owner_membership).none?

  # Said once, here, and served to the client rather than written out
  # again in the template that shows it — the rule and its wording belong
  # together, and two copies in two languages drift.
  EMPTY_FIRST = 'Take the submissions out and remove everyone else — including invitations nobody has used — first.'.freeze

  # A conversation is not the owner's to erase, and unlike the other two
  # blockers there is nothing anybody can do to clear it: a thread is
  # DDBJ's record of what was asked and answered, and the curator who
  # answered has no copy anywhere else. Said as a fact rather than as an
  # instruction, because there is no step that unblocks it.
  CONVERSATION_KEPT = 'This set has a conversation with DDBJ on it, which is the record of what was asked and answered — so the set stays.'.freeze

  def delete_blocked_reason
    return CONVERSATION_KEPT if messages.exists?

    deletable? ? nil : EMPTY_FIRST
  end

  # Everything below mirrors SubmissionRequest's thread deliberately,
  # name for name: a curator moves between the two axes all day, and the
  # rules are the same rules. What differs is who the other side is —
  # a roster rather than one submitter — which is why reading has two
  # markers rather than one.

  # What is waiting on THIS curator: unanswered by any curator, and not
  # already put aside by them. No marker means "nothing put aside", so
  # picking up a set whose conversation was settled long ago does not
  # report its history as unread.
  def unread_message_count_for(user)
    return 0 unless user

    marker = participations.find_by(user_id: user.id)&.last_read_at
    scope  = messages.unanswered
    scope  = scope.where('submission_set_messages.created_at > ?', marker) if marker

    scope.count
  end

  # Claiming says who is answering; it is not a claim to have read
  # anything, and it must not discharge the question that prompted it —
  # so no marker and no subscription here, exactly as on a request.
  def assign!(user)
    raise ArgumentError, 'Assignee must be an admin user.' unless user.nil? || user.admin?

    update!(assignee: user)
  end

  # "I have seen this thread, up to here." `through` is the newest
  # message the reader had in front of them, so a message that lands
  # while a reply is being typed is not discharged unseen.
  #
  # `as:` is passed rather than read off the account, and that is the
  # whole of it: which side somebody is acting from is a fact about the
  # screen they pressed the button on. A curator can be a member of a set
  # like anybody else, and inferring the side from `admin?` gave that
  # person a badge they could never clear — and, worse, let a press on
  # the member's side dismiss a curator queue entry they had never seen
  # as a curator.
  #
  # Returns whether anything moved, so a screen does not report having
  # marked what it did not: a `through` naming a message from another set
  # (a stale tab, a hand-edited form) marks nothing.
  def mark_read_by!(user, as:, through: nil)
    return false unless user

    at = through ? messages.where(id: through).pick(:created_at) : Time.current
    return false unless at

    marked =
      case as
      when :curator then mark_curator_read(user, at)
      when :member  then mark_member_read(user, at)
      else raise ArgumentError, "unknown side: #{as.inspect}"
      end

    marked.positive?
  end

  # Who hears about a message here, apart from whoever wrote it. Asked by
  # the mailer and by the caller deciding whether there is anything to
  # send, so the two cannot drift.
  def followers_to_notify(message) = followers.reject { it.id == message.user_id }

  def following?(user)
    return false unless user

    participations.subscribed.exists?(user_id: user.id)
  end

  # Posting follows it from then on: a curator who steps back in has
  # stepped back in. Marking read is the opposite and does not come
  # through here.
  def subscribe!(user)
    participate!(user)
    participations.where(user_id: user.id).update_all(unsubscribed_at: nil)
  end

  def unsubscribe!(user)
    participate!(user)
    participations.where(user_id: user.id).update_all(unsubscribed_at: Time.current)
  end

  # A side effect of a curator doing something here, so it must never
  # fail the action it hangs off: already-a-participant is a no-op, and a
  # member acting in their own set is simply not a participant.
  def participate!(user)
    return unless user&.admin?

    SubmissionSetParticipant.insert_all(
      [{submission_set_id: id, user_id: user.id, created_at: Time.current, updated_at: Time.current}],
      unique_by: %i[submission_set_id user_id]
    )
  end

  private

  # Creates the row it writes on, but NOT as a subscription:
  # acknowledging a thread is the opposite of asking to hear more about
  # it. An existing row keeps whatever it said, so this never
  # unsubscribes anybody either.
  def mark_curator_read(user, at)
    SubmissionSetParticipant.insert_all(
      [{submission_set_id: id, user_id: user.id, created_at: Time.current, updated_at: Time.current,
        unsubscribed_at:   Time.current}],
      unique_by: %i[submission_set_id user_id]
    )

    advance_marker participations.where(user_id: user.id), at
  end

  # No row to create — a member already has one, and somebody who is not
  # on the roster is not reading this thread at all.
  def mark_member_read(user, at) = advance_marker(members.joined.where(user_id: user.id), at)

  # Never backwards: a stale tab rendered when more was unread would
  # otherwise reset the position and resurrect everything already dealt
  # with.
  def advance_marker(scope, at)
    scope.where('last_read_at IS NULL OR last_read_at < ?', at).update_all(last_read_at: at)
  end

  def owner_membership = members.where(user_id: owner_id).select(:id)
end
