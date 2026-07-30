class User < ApplicationRecord
  def self.generate_api_key
    SecureRandom.base58(32)
  end

  has_many :submission_requests

  has_many :submissions
  has_many :submission_updates, through: :submissions, source: :updates

  scope :with_submission_requests, -> { where(id: SubmissionRequest.select(:user_id)) }
  scope :staff,                    -> { where(admin: true) }

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
