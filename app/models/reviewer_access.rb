# A shareable, unguessable link onto one set — /web/reviews/<token> — and
# the accessions its members have put on it.
#
# It carries nothing until an accession is named. That is the whole
# difference from what it replaces: a link per submission request, which
# carried the entire request the moment it existed — the uploaded record,
# the applied record, both flatfiles — and which meant handing a reviewer
# one link per submission. Nobody sharing data with a journal reviewer
# meant either of those things.
#
# Who may do what follows the set's own rule (see SubmissionSet). Any
# member may enable the link, move its expiry and revoke it, because a
# collaboration is not organised around whoever pressed New first — and
# because revoking is the safe direction, which is the one a member must
# never have to wait for somebody else to take.
#
# What it carries is narrower, and deliberately so: each accession is put
# on by the owner of the submission it belongs to, and only they can take
# it off. Reading somebody's submission through a set has never been the
# right to hand it on, and an anonymous link is as far on as it gets.
class ReviewerAccess < ApplicationRecord
  belongs_to :set, class_name: 'SubmissionSet', foreign_key: :submission_set_id, inverse_of: :reviewer_access

  # Whoever minted the token currently in force — not a role. Kept for the
  # same reason SubmissionSetInclusion keeps `added_by`: an account can be
  # proxied, and "who did this" is the question a support thread asks.
  belongs_to :created_by, class_name: 'User'

  has_many :shared_accessions, -> { order(:accession) },
           class_name: 'ReviewerAccessAccession', dependent: :destroy, inverse_of: :reviewer_access

  # What one link may carry. A property of the link rather than of the
  # endpoint that fills it: the reviewer's list is drawn in one page
  # because of this, and `shared_rows` resolves in three queries however
  # long the list is — but a link naming a hundred thousand samples is not
  # a review link, it is the whole submission by another route.
  MAX_SHARED = 1_000

  # Unguessable share token — the reviewer URL is /web/reviews/<token>.
  TOKEN_LENGTH = 32

  has_secure_token :token, length: TOKEN_LENGTH

  validates :expires_at, presence: true

  # On every write, not only on create. A row is only ever written by
  # `enable!` below, and both of the things that does — handing out a
  # first URL and handing out a replacement — produce a link somebody is
  # about to send to a reviewer. One that arrives already dead is a
  # support thread rather than an error.
  validate :expires_at_in_future

  # Live links only — an expired token must read as "not found" to a
  # reviewer, never as a revoked-but-recognised one.
  scope :active, -> { where(expires_at: Time.current..) }

  # Enabling and re-minting are the same act: the set gets a link, and it
  # gets a URL nobody has seen before. Here rather than in the controller
  # because the half that matters is the half that does not happen — the
  # accessions on the link are left exactly as they were.
  def self.enable!(set, created_by:, expires_at:)
    access = set.reviewer_access || set.build_reviewer_access

    access.update!(created_by:, expires_at:, token: generate_unique_secure_token(length: TOKEN_LENGTH))

    access
  end

  def expired?
    expires_at.past?
  end

  def full? = shared_accessions.count >= MAX_SHARED

  # What the link actually shows, which is not simply what was named on
  # it. Every accession is resolved through the set's current contents, so
  # a submission taken out of the set stops being on the link the moment
  # it goes — regardless of what rows are left behind. Taking a submission
  # out also deletes the rows (SubmissionSetInclusion), and that is the
  # tidying; this is the guarantee.
  def shared_rows = set.accession_rows(shared_accessions.pluck(:accession))

  # The shareable link the set hands to a reviewer. Points at the Ember
  # SPA route (/web/reviews/<token>), not the API.
  def share_url
    WebApp.url_for("/reviews/#{token}")
  end

  private

  def expires_at_in_future
    return if expires_at.blank? || expires_at.future?

    errors.add(:expires_at, 'must be in the future')
  end
end
