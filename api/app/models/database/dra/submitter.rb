class Database::DRA::Submitter
  ACC_TYPES = {
    "Submission" => "DRA",
    "Experiment" => "DRX",
    "Run"        => "DRR",
    "Analysis"   => "DRZ"
  }

  def submit(submission)
    submitter_id = submission.validation.user.uid
    user_id      = SubmitterDB::Login.where(submitter_id:).pick(:usr_id)

    DRMDB::Record.transaction isolation: Rails.env.test? ? nil : :serializable do
      serial = (DRMDB::Submission.where(submitter_id:).maximum(:serial) || 0) + 1

      dra_submission = DRMDB::Submission.create!(
        usr_id:       user_id,
        submitter_id:,
        serial:,
        create_date:  Date.current
      )

      dra_submission.status_histories.create!(
        status: :new
      )

      submission_group = dra_submission.create_submission_group!(
        submit_version: 1,
        valid:          true,
        serial_version: 1
      )

      DRMDB::OperationHistory.create!(
        type:         :info,
        summary:      "Status update to new",
        usr_id:       user_id,
        serial:,
        submitter_id:
      )

      submission_id = "#{submitter_id}-#{serial.to_s.rjust(4, '0')}"

      entity = DRMDB::ExtEntity.create!(
        acc_type: :submission,
        ref_name: submission_id,
        status:   :inputting
      )

      DRMDB::ExtPermit.create!(
        ext_id: entity.ext_id,
        submitter_id:
      )

      host, user, key_data = ENV.values_at("DRA_SSH_HOST", "DRA_SSH_USER", "DRA_SSH_KEY_DATA")

      Net::SSH.start host, user, key_data: [ key_data ] do |ssh|
        ssh.exec! "sudo /usr/local/sbin/chroot-createdir.sh #{submitter_id} #{submission_id}"
      end

      submission.validation.objs.where(_id: ACC_TYPES.keys).each do |obj|
        submission_group.accession_relations.create! do |relation|
          relation.accession_entities.create!(
            alias:       "#{submission_id}_#{obj._id}_0001",
            center_name: "National Institute of Genetics",
            acc_type:    ACC_TYPES.fetch(obj._id),
          )

          relation.create_meta_entitiy!(
            meta_version: 0,
            type:         obj._id.downcase,
            content:      obj.file.download
          )
        end
      end
    end
  end
end
