# One person's place in one set — whether they have accepted yet or
# not.
#
# "Add a member" is a single action, so it leaves a single row, and the
# roster is one list rather than a list of members beside a list of
# outstanding invitations. `user_id` is what separates the two states:
# absent means the invitation is still out.
#
# The invitation is a token in a link, not a match on the address. An
# address is what the inviter typed and what the mail was sent to; it is
# NOT what is checked on the way in, because the person who receives it
# may not have a DDBJ Account yet and may well create one under a
# different address — matching on the address would leave them at a dead
# end with nothing on screen to explain it. What the token costs is that
# a forwarded mail lets somebody else in, so the row records which
# account accepted and the roster shows it whenever that account's
# address is not the one invited. Forwarding an invitation to a
# colleague is a real thing people do; the answer is to make it visible,
# not to refuse it.
class SubmissionSetMember < ApplicationRecord
  # Long, because what an invitation waits for is not the round trip —
  # it is somebody getting round to it.
  INVITATION_VALIDITY = 30.days

  # `set` is the word everywhere else — the class is SubmissionSet only
  # because Ruby owns the constant `Set`.
  belongs_to :set, class_name: 'SubmissionSet', foreign_key: :submission_set_id, inverse_of: :members
  belongs_to :user, optional: true
  belongs_to :invited_by, class_name: 'User'

  normalizes :email, with: -> { it.presence&.strip&.downcase }

  # Required of an invitation and of nothing else: the creator's own row
  # was never invited, and a joined member's address is their account's.
  validates :email, presence: true, if: :pending?
  validates :email, format: {with: URI::MailTo::EMAIL_REGEXP}, uniqueness: {scope: :submission_set_id}, allow_nil: true
  validates :user_id, uniqueness: {scope: :submission_set_id}, allow_nil: true

  validate :not_already_joined, on: :create, if: :pending?

  scope :joined,  -> { where.not(user_id: nil) }
  scope :pending, -> { where(user_id: nil) }
  scope :ordered, -> { order(:created_at, :id) }

  before_validation :issue_invitation!, on: :create, unless: :joined?

  def pending? = user_id.nil?
  def joined?  = !pending?

  def invitation_expired? = pending? && invitation_expires_at.past?

  # What the link says about itself. `accepted` exists because the token
  # is kept after it has been walked through: somebody opening the mail a
  # second time — from their phone, a week later — is told what happened
  # rather than shown a 404 for a link that worked perfectly.
  def invitation_state
    return 'accepted' if joined?

    invitation_expired? ? 'expired' : 'open'
  end

  # Whether the mail we send on an invitation actually leaves the
  # building. Every deployed environment restricts outgoing mail while
  # sending to real submitters is switched off, which would otherwise
  # make this feature look like it works and quietly reach nobody — the
  # roster says so, and offers the link to send by hand.
  def deliverable? = email.present? && MailDomainAllowlistInterceptor.delivers_to?(email)

  # Whether the account that walked through the invitation is registered
  # at the address it was sent to. Three answers, not two: an account
  # imported from D-way that has never signed in carries no address at
  # all, and saying `same` for one of those would put a claim on the
  # roster that nothing checked. `unknown` is the honest word, and this
  # is the whole of the audit that pays for not binding the token to the
  # address.
  #
  # nil where the question does not arise — the creator's own row, which
  # was never invited.
  def invited_address_match
    return nil unless joined? && email.present?
    return 'unknown' if user&.email.blank?

    user.email.downcase == email ? 'same' : 'different'
  end

  # The token is deliberately NOT cleared: see the check constraint. It
  # grants nothing from here — every path that acts on an invitation
  # refuses a row that has been joined — and keeping it is what lets the
  # link explain itself when it is opened again.
  def accept!(acceptor)
    update!(user: acceptor, joined_at: Time.current, invitation_expires_at: nil)
  end

  # The link that was mailed. Points at the SPA, which is where the page
  # explaining the invitation lives.
  def invitation_url = invitation_token && WebApp.url_for("/invitations/#{invitation_token}")

  # Taking somebody off the roster takes with them everything their being
  # here brought in.
  #
  # **Their submissions**, because the set was the only thing letting
  # the others read that work; leaving it behind would go on sharing it
  # after the person who put it there has gone, and they would have no
  # way of noticing, since the set is no longer on their screen.
  #
  # **The invitations they sent**, because any member may invite. Without
  # this, somebody who is asked to leave walks back in through a link
  # they mailed to themselves a month earlier — and removal, which is the
  # only revocation this design has, would revoke nothing.
  #
  # NOT an invitation somebody else sent *to* them: that is the other
  # member's, and taking it back is theirs to do. Removing a person who
  # has an outstanding invitation from a colleague therefore leaves a way
  # back in — visible on the roster, which is where it belongs.
  #
  # Under a lock on the set. Serialising the writers is only half of it
  # — a write that queues behind this one still believed it was a member
  # when it started — so every write that adds to a set takes the same
  # lock and asks again inside it (SetContents#within_set_membership).
  # Without that half, a submission added mid-sweep is left behind: in the
  # set, readable by everyone in it, and unreachable by its owner, for
  # whom the set is no longer on screen.
  def remove!
    set.with_lock do
      if joined?
        set.inclusions
             .joins(:submission_request)
             .where(submission_requests: {user_id: user_id})
             .destroy_all

        set.members.pending.where(invited_by_id: user_id).destroy_all
      end

      destroy!
    end
  end

  # A fresh token and a fresh clock. The old link stops working, which is
  # what somebody asking for a resend expects — they are replacing a link
  # that did not get used, not handing out a second one.
  #
  # Refused on a joined row here rather than only in the controller: the
  # database would refuse it too (the state constraint), and a check
  # constraint surfacing as a 500 is not the way anybody should find out.
  def resend!
    raise ArgumentError, 'That person has already joined.' if joined?

    issue_invitation!
    save!
  end

  private

  # Inviting somebody who is already here is a misfire rather than a
  # second seat — and the unique index would not catch it, since it is
  # their account's address being matched and not the one they were
  # invited at.
  def not_already_joined
    return if email.blank? || set.nil?

    return unless set.members.joined.joins(:user).where('lower(users.email) = ?', email).exists?

    errors.add(:email, 'is already a member of this set')
  end

  def issue_invitation!
    self.invitation_token      = self.class.generate_unique_secure_token(length: 32)
    self.invitation_expires_at = INVITATION_VALIDITY.from_now
  end
end
