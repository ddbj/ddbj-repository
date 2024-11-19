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

      submission_group = dra_submission.create_submission_group!(
        submit_version: 1,
        valid:          true,
        serial_version: 1
      )

      submission_id = "#{submitter_id}-#{serial.to_s.rjust(4, '0')}"

      submission.validation.objs.where(_id: ACC_TYPES.keys).each do |obj|
        acc_entity = DRMDB::AccessionEntity.create!(
          alias:       "#{submission_id}_#{obj._id}_0001",
          center_name: "National Institute of Genetics",
          acc_type:    ACC_TYPES.fetch(obj._id),
        )

        submission_group.accession_relations.create! acc_id: acc_entity.acc_id do |relation|
          relation.build_meta_entity(
            acc_id:       acc_entity.acc_id,
            meta_version: 1,
            type:         obj._id.downcase,
            content:      obj.file.download
          )
        end

        ext_entity = DRMDB::ExtEntity.create!(
          acc_type: :submission,
          ref_name: "160053",
          status:   :valid
        )

        submission_group.ext_relations.create!(
          acc_id: acc_entity.acc_id,
          ext_id: ext_entity.ext_id
        ) do |relation|
          relation.build_ext_permit(
            ext_id:       ext_entity.ext_id,
            submitter_id:
          )
        end
      end

      host, user, key_data = ENV.values_at("DRA_SSH_HOST", "DRA_SSH_USER", "DRA_SSH_KEY_DATA")

      Net::SSH.start host, user, key_data: [ key_data ] do |ssh|
        ssh.exec! "sudo /usr/local/sbin/chroot-createdir.sh #{submitter_id} #{submission_id}"
      end
    end
  end
end
