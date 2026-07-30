# Pulls contact addresses from Cloakman into `users.email`.
#
# Logins keep the column fresh for anyone who actually uses the app, but
# the D-way importer creates accounts from a uid alone — the submitters a
# release notice is aimed at have typically never logged in here. Without
# this sync their address stays unknown and every mail to them falls back
# to the placeholder.
class SyncUserEmailsJob < ApplicationJob
  def perform
    changed = User.sync_emails!

    Rails.logger.info "[sync_user_emails] updated #{changed} address(es)"
  end
end
