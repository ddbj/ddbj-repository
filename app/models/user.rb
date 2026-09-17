class User < ApplicationRecord
  def self.generate_api_key
    SecureRandom.base58(32)
  end

  has_many :submission_requests

  has_many :submissions
  has_many :submission_updates, through: :submissions, source: :updates

  # Named ledger filters. Personal, so they go when the account does.
  has_many :saved_views, dependent: :destroy

  # Sets this account belongs to. No `dependent` on either: a set is
  # shared work rather than one person's, so an account cannot take one
  # with it — the foreign key refuses the deletion, which is the honest
  # answer until somebody decides what handing a set over looks like.
  has_many :submission_set_members, dependent: nil
  has_many :submission_sets, through: :submission_set_members
  has_many :owned_submission_sets, class_name: 'SubmissionSet', inverse_of: :owner, foreign_key: :owner_id, dependent: nil

  belongs_to :notes_updated_by, class_name: 'User', optional: true

  # Data files this account has uploaded and not let go of: where a file waits
  # between being uploaded and being named in a submission — minutes for most,
  # days for reads uploaded ahead of their metadata. The place D-way's
  # `/submission/upload/<submitter>` directory was. Attached, so
  # PurgeUnattachedUploadsJob, which collects what nobody attached, leaves them
  # alone.
  #
  # No `dependent`. Taking a file out of here detaches it and nothing more: once
  # submissions name data files, the blob one names must not go with it.
  # Whatever is then attached to nothing is PurgeUnattachedUploadsJob's to
  # collect.
  has_many_attached :data_files, dependent: false

  scope :with_submission_requests, -> { where(id: SubmissionRequest.select(:user_id)) }
  scope :staff,                    -> { where(admin: true) }
  scope :submitters,               -> { where(admin: false) }

  # Prefix on the uid — the identifier a curator is most often holding.
  # Name and organization are not ours to search: DDBJ Account holds them,
  # and CloakmanClient#search is what covers them.
  scope :uid_matching, ->(prefix) {
    where('uid ILIKE ?', "#{sanitize_sql_like(prefix)}%")
  }

  # Notes are shared between curators, so who wrote them last is part of
  # the content. Written together for the same reason.
  def update_notes!(body, by:)
    update!(notes: body.to_s, notes_updated_by: by, notes_updated_at: Time.current)
  end

  before_create do |user|
    user.api_key ||= self.class.generate_api_key
  end

  # Uids per Cloakman lookup. They ride in the query string, so this trades
  # URL length against round trips.
  SYNC_BATCH_SIZE = 200

  # `email` is a local copy of the address Cloakman holds, refreshed from the
  # id token on every login (SessionsController#create) — mail delivery reads
  # the column so it never depends on Cloakman being up.
  #
  # Accounts created by the D-way importer have never logged in, so their
  # column starts empty; this fills them in bulk (SyncUserEmailsJob, nightly).
  # Cloakman is the authority, so a profile it has no email for clears the
  # column rather than leaving a stale address behind. A uid it doesn't know
  # at all is left alone. Returns the number of addresses changed.
  def self.sync_emails!(scope = all)
    client  = CloakmanClient.new
    changed = 0

    scope.pluck(:uid).each_slice(SYNC_BATCH_SIZE) do |uids|
      emails = client.lookup(uids).to_h { [it['uid'], it['email'].presence] }

      where(uid: emails.keys).each do |user|
        email = emails[user.uid]
        next if user.email == email

        user.update_column(:email, email)
        changed += 1
      end
    end

    changed
  end

  def token
    JWT.encode({user_id: id}, Rails.application.secret_key_base, 'HS512')
  end
end
