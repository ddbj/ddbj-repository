class AddMailStatusToAccessionIssuances < ActiveRecord::Migration[8.1]
  # What became of the notification, recorded rather than inferred.
  #
  # The run page used to read it off `error_message`: blank meant sent.
  # That is true of a delivery that failed and of nothing else — a
  # submitter with no address on file, and every address outside the
  # environment's mail allowlist, were both reported as "sent 09:31".
  # Inferring it again at render time would be worse than wrong: the
  # allowlist is temporary, and the day it is lifted every past run would
  # start claiming it had mailed people it never mailed.
  def up
    add_column :accession_issuances, :mail_status, :string

    # Existing rows predate the distinction, and only a completed one
    # ever attempted a mail. Blank error_message meant sent under the old
    # reading, which is the best that can be said of them now.
    execute <<~SQL.squish
      UPDATE accession_issuances
      SET    mail_status = CASE WHEN error_message IS NULL THEN 'sent' ELSE 'failed' END
      WHERE  status = 'completed'
    SQL
  end

  def down
    remove_column :accession_issuances, :mail_status
  end
end
