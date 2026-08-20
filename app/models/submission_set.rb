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
  def deletable? = inclusions.none? && members.where.not(id: owner_membership).none?

  # Said once, here, and served to the client rather than written out
  # again in the template that shows it — the rule and its wording belong
  # together, and two copies in two languages drift.
  EMPTY_FIRST = 'Take the submissions out and remove everyone else — including invitations nobody has used — first.'.freeze

  def delete_blocked_reason = deletable? ? nil : EMPTY_FIRST

  private

  def owner_membership = members.where(user_id: owner_id).select(:id)
end
