class Database::DRA::Submitter
  def submit(submission)
    submitter_id = submission.validation.user.uid
    user_id      = SubmitterDB::Login.where(submitter_id:).pick(:usr_id)

    DRMDB::Record.transaction isolation: Rails.env.test? ? nil : :serializable do
      serial        = (DRMDB::Submission.where(submitter_id:).maximum(:serial) || 0) + 1
      submission_id = "#{submitter_id}-#{serial.to_s.rjust(4, '0')}"

      submission = DRMDB::Submission.create!(
        usr_id:       user_id,
        submitter_id:,
        serial:,
        create_date:  Date.current
      )

      submission.status_histories.create!(
        status: :new
      )

      DRMDB::OperationHistory.create!(
        type:         :info,
        summary:      "Status update to new",
        usr_id:       user_id,
        serial:,
        submitter_id:
      )

      DRMDB::ExtEntity.create!(
        acc_type: :submission,
        ref_name: submission_id,
        status:   :inputting
      ) do |entity|
        entity.ext_permits.build(
          submitter_id:
        )
      end

      host, user, key_data = ENV.values_at("DRA_SSH_HOST", "DRA_SSH_USER", "DRA_SSH_KEY_DATA")

      Net::SSH.start host, user, key_data: [ key_data ] do |ssh|
        ssh.exec! "sudo /usr/local/sbin/chroot-createdir.sh #{submitter_id} #{submission_id}"
      end
    end
  end
end
